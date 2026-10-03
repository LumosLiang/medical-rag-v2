from fastapi.testclient import TestClient
import pytest

from medical_rag.backend.api import app, get_client
from medical_rag.backend.schemas import Completion, QueryRequest, Source
from medical_rag.backend.rag import answer_question


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
    result = answer_question(QueryRequest(question="效果如何？"), client, "baseline")
    assert result.sources[0].cited
    assert result.sources[0].page_start == 0
    assert result.sources[0].chunk_id == "chunk-1"


def test_no_results_skips_generation():
    client = FakeClient(empty=True)
    result = answer_question(QueryRequest(question="效果如何？"), client, "baseline")
    assert result.insufficient_evidence
    assert client.complete_calls == 0


@pytest.mark.parametrize("answer", ["结论 [99]。", "结论没有引用。"])
def test_invalid_or_missing_citations_are_rejected(answer):
    with pytest.raises(ValueError):
        answer_question(QueryRequest(question="效果如何？"), FakeClient(answer), "baseline")


def test_api_rejects_invalid_requests_before_querying_snowflake():
    with TestClient(app) as client:
        assert client.post("/ask", json={"question": " "}).status_code == 422
        assert client.post("/search", json={"question": "x", "top_k": 11}).status_code == 422
