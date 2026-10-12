from fastapi import HTTPException
from fastapi.testclient import TestClient
import pytest

from medical_rag.backend.api import app
from medical_rag.backend.models import Completion, QueryRequest, Source
from medical_rag.backend import api


class FakeClient:
    def __init__(self, answer="研究报告了改善 [1]。", empty=False, insufficient=False):
        self.answer = answer
        self.empty = empty
        self.insufficient = insufficient
        self.complete_calls = 0

    def search(self, request):
        if self.empty:
            return []
        return [Source(citation_id=1, chunk_id="chunk-1", relative_path="PMC1.pdf",
                       page_start=0, page_end=0, text="Reported improvement.")]

    def complete(self, prompt):
        self.complete_calls += 1
        assert "Reported improvement." in prompt
        return Completion(answer=self.answer, insufficient_evidence=self.insufficient)


def test_answer_preserves_real_source_and_page():
    client = FakeClient()
    result = api.ask(QueryRequest(question="效果如何？"), retrieval_service=client, generation_service=client)
    assert result.sources[0].cited
    assert result.sources[0].page_start == 0
    assert result.sources[0].chunk_id == "chunk-1"


def test_no_results_skips_generation():
    client = FakeClient(empty=True)
    result = api.ask(QueryRequest(question="效果如何？"), retrieval_service=client, generation_service=client)
    assert result.insufficient_evidence
    assert client.complete_calls == 0


@pytest.mark.parametrize("answer", ["结论 [99]。", "结论没有引用。"])
def test_invalid_or_missing_citations_are_rejected(answer):
    client = FakeClient(answer)
    with pytest.raises(HTTPException) as error:
        api.ask(QueryRequest(question="效果如何？"), retrieval_service=client, generation_service=client)
    assert error.value.status_code == 502


def test_api_rejects_invalid_requests_before_querying_snowflake():
    with TestClient(app) as client:
        assert client.post("/ask", json={"question": " "}).status_code == 422
        assert client.post("/search", json={"question": "x", "top_k": 11}).status_code == 422


def test_ask_http_rejects_invalid_citation():
    fake = FakeClient(answer="结论 [99]。")
    app.dependency_overrides[api.get_retrieval_service] = lambda: fake
    app.dependency_overrides[api.get_generation_service] = lambda: fake
    try:
        with TestClient(app) as client:
            response = client.post("/ask", json={"question": "效果如何？"})
        assert response.status_code == 502
        assert "不存在的引用编号" in response.json()["detail"]
    finally:
        app.dependency_overrides.clear()
