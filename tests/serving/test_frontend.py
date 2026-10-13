from pathlib import Path

import httpx
from streamlit.testing.v1 import AppTest


APP = Path(__file__).resolve().parents[2] / "src/serving/medical_rag/frontend/app.py"


def submit(at):
    at.text_area[0].input("研究纳入多少人？")
    at.checkbox[0].check()
    for button in at.button:
        if button.label == "查询":
            button.click()
    at.run()
    assert not at.exception


def test_frontend_displays_claim_quote_real_page_and_complete_source(monkeypatch):
    result = {
        "answer": "该研究纳入120名成年人。 [1]",
        "claims": [{"text": "该研究纳入120名成年人。", "citations": [
            {"source_id": 1, "quote": "The study enrolled 120 adults."}
        ]}],
        "insufficient_evidence": False,
        "config_name": "test-config",
        "sources": [{"citation_id": 1, "chunk_id": "chunk-1", "relative_path": "PMC1.pdf",
                     "page_start": 0, "page_end": 1, "cited": True,
                     "text": "The study enrolled 120 adults. Follow-up was six months."}],
    }

    def post(url, **kwargs):
        return httpx.Response(200, json=result, request=httpx.Request("POST", url))

    monkeypatch.setattr(httpx, "post", post)
    at = AppTest.from_file(str(APP)).run()
    submit(at)
    assert result["answer"] in [item.value for item in at.markdown]
    assert "The study enrolled 120 adults." in [item.value for item in at.text]
    assert result["sources"][0]["text"] in [item.value for item in at.text]
    assert "对应结论：该研究纳入120名成年人。" in [item.value for item in at.caption]
    assert "第 1–2 页" in at.expander[1].label
    assert len(at.session_state["turns"]) == 1


def test_frontend_shows_validation_error_without_saving_an_answer(monkeypatch):
    def post(url, **kwargs):
        return httpx.Response(502, json={"detail": "引用摘录未通过校验"},
                              request=httpx.Request("POST", url))

    monkeypatch.setattr(httpx, "post", post)
    at = AppTest.from_file(str(APP)).run()
    submit(at)
    assert at.error[0].value == "引用摘录未通过校验"
    assert at.session_state["turns"] == []
