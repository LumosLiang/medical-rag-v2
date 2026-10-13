from fastapi import HTTPException
from fastapi.testclient import TestClient
import pytest

from medical_rag.backend.api import app
from medical_rag.backend.models import Claim, Citation, Completion, QueryRequest, Source
from medical_rag.backend import api


class FakeClient:
    def __init__(self, claims=None, empty=False, insufficient=False):
        if claims is None:
            claims = [Claim(text="该研究纳入120名成年人。", citations=[
                Citation(source_id=1, quote="The study enrolled 120 adults.")
            ])]
        self.claims = claims
        self.empty = empty
        self.insufficient = insufficient
        self.complete_calls = 0

    def search(self, request):
        if self.empty:
            return []
        return [Source(citation_id=1, chunk_id="chunk-1", relative_path="PMC1.pdf",
                       page_start=0, page_end=0,
                       text="The study enrolled 120 adults.\nThe change was -6.1, with p ≤ 0.05.")]

    def complete(self, prompt):
        self.complete_calls += 1
        assert "The study enrolled 120 adults." in prompt
        return Completion(claims=self.claims, insufficient_evidence=self.insufficient)


def ask(fake):
    return api.ask(QueryRequest(question="这项研究报告了什么？"),
                   retrieval_service=fake, generation_service=fake)


def test_answer_preserves_source_page_quote_and_generates_marker():
    result = ask(FakeClient())
    assert result.answer == "该研究纳入120名成年人。 [1]"
    assert result.claims[0].citations[0].quote == "The study enrolled 120 adults."
    assert result.sources[0].cited
    assert result.sources[0].page_start == 0
    assert result.sources[0].chunk_id == "chunk-1"


def test_no_results_skips_generation():
    fake = FakeClient(empty=True)
    result = ask(fake)
    assert result.insufficient_evidence
    assert result.claims == []
    assert fake.complete_calls == 0


@pytest.mark.parametrize("insufficient", [False, True])
def test_missing_citation_on_second_claim_is_rejected_even_when_insufficient(insufficient):
    fake = FakeClient(insufficient=insufficient)
    fake.claims.append(Claim(text="随访六个月。", citations=[]))
    with pytest.raises(HTTPException) as error:
        ask(fake)
    assert error.value.status_code == 502
    assert "缺少证据引用" in error.value.detail


@pytest.mark.parametrize("source_id,quote", [
    (99, "The study enrolled 120 adults."),
    (1, "The study enrolled 200 adults."),
    (1, "The change was 6.1, with p ≤ 0.05."),
    (1, "The change was -6.1, with p ≥ 0.05."),
    (1, "   "),
])
def test_invalid_source_or_fabricated_quote_is_rejected(source_id, quote):
    claim = Claim(text="研究结果。", citations=[Citation(source_id=source_id, quote=quote)])
    with pytest.raises(HTTPException) as error:
        ask(FakeClient(claims=[claim]))
    assert error.value.status_code == 502


def test_quote_can_differ_only_in_whitespace():
    quote = "The study enrolled 120 adults.  \n The change was -6.1, with p ≤ 0.05."
    claim = Claim(text="研究结果。", citations=[Citation(source_id=1, quote=quote)])
    assert ask(FakeClient(claims=[claim])).sources[0].cited


def test_multiple_quotes_from_one_source_render_one_marker():
    citations = [Citation(source_id=1, quote="The study enrolled 120 adults."),
                 Citation(source_id=1, quote="The change was -6.1, with p ≤ 0.05.")]
    result = ask(FakeClient(claims=[Claim(text="研究结果。", citations=citations)]))
    assert result.answer.count("[1]") == 1
    assert len(result.claims[0].citations) == 2


def test_model_cannot_embed_its_own_citation_marker():
    fake = FakeClient()
    fake.claims[0].text = "研究结果 [99]。"
    with pytest.raises(HTTPException) as error:
        ask(fake)
    assert error.value.status_code == 502


def test_empty_claims_without_insufficient_flag_are_rejected():
    with pytest.raises(HTTPException) as error:
        ask(FakeClient(claims=[]))
    assert error.value.status_code == 502


def test_insufficient_answer_uses_fixed_message():
    result = ask(FakeClient(claims=[], insufficient=True))
    assert result.answer == "现有检索证据不足以完整回答这个问题。"
    assert result.sources and not result.sources[0].cited


def test_partial_answer_keeps_valid_claim_and_marks_insufficiency():
    result = ask(FakeClient(insufficient=True))
    assert result.claims and result.insufficient_evidence
    assert result.answer.endswith("现有检索证据不足以完整回答这个问题。")


def test_api_rejects_invalid_requests_before_querying_snowflake():
    with TestClient(app) as client:
        assert client.post("/ask", json={"question": " "}).status_code == 422
        assert client.post("/search", json={"question": "x", "top_k": 11}).status_code == 422


def test_http_error_does_not_expose_unverified_claim():
    fake = FakeClient(claims=[Claim(text="未经核验的结论", citations=[])])
    app.dependency_overrides[api.get_retrieval_service] = lambda: fake
    app.dependency_overrides[api.get_generation_service] = lambda: fake
    try:
        with TestClient(app) as client:
            response = client.post("/ask", json={"question": "效果如何？"})
        assert response.status_code == 502
        assert set(response.json()) == {"detail"}
        assert "未经核验的结论" not in response.text
    finally:
        app.dependency_overrides.clear()


def test_invalid_model_json_returns_controlled_http_error():
    fake = FakeClient()

    class InvalidGeneration:
        def complete(self, prompt):
            raise ValueError("raw invalid model output")

    with pytest.raises(HTTPException) as error:
        api.ask(QueryRequest(question="效果如何？"), retrieval_service=fake,
                generation_service=InvalidGeneration())
    assert error.value.status_code == 502
    assert "raw invalid" not in error.value.detail
