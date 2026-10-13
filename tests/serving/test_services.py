"""覆盖服务边界：SDK 请求、结果映射、模型响应和配置读取。"""
from contextlib import contextmanager
import json
from types import SimpleNamespace

import pytest
from snowflake.core.cortex.search_service import QueryResponse

from medical_rag.backend.models import QueryRequest
from medical_rag.backend.services import generation, retrieval
from medical_rag.backend.settings import Settings


@pytest.mark.parametrize("relative_path", [None, "PMC1.pdf"])
def test_retrieval_maps_sdk_response(monkeypatch, relative_path):
    settings = Settings()
    captured = {}

    class SearchService:
        def search(self, **parameters):
            captured.update(parameters)
            return QueryResponse(
                request_id="test-request",
                results=[{
                    "CHUNK_ID": "chunk-1",
                    "RELATIVE_PATH": "PMC1.pdf",
                    "PAGE_START": 0,
                    "PAGE_END": 1,
                    "CHUNK_TEXT": "Original evidence.",
                }],
            )

    service = SearchService()
    schema = SimpleNamespace(cortex_search_services={settings.search_service: service})
    database = SimpleNamespace(schemas={settings.schema: schema})
    root = SimpleNamespace(databases={settings.database: database})

    @contextmanager
    def fake_connection(settings):
        yield object()

    monkeypatch.setattr(retrieval, "connect", fake_connection)
    monkeypatch.setattr(retrieval, "Root", lambda connection: root)

    request = QueryRequest(question="治疗效果如何？", top_k=3, relative_path=relative_path)
    sources = retrieval.RetrievalService(settings).search(request)

    assert captured["query"] == request.question
    assert captured["limit"] == 3
    assert captured["scoring_config"] == settings.scoring_config
    if relative_path is None:
        assert captured["filter"] is None
    else:
        assert captured["filter"] == {"@eq": {"RELATIVE_PATH": relative_path}}
    assert sources[0].chunk_id == "chunk-1"
    assert sources[0].citation_id == 1
    assert sources[0].text == "Original evidence."
    assert sources[0].page_end == 1


@pytest.mark.parametrize("empty_response", [False, True])
def test_generation_response_format_and_empty_result(monkeypatch, empty_response):
    captured = {}

    class Cursor:
        def execute(self, sql, parameters):
            captured["parameters"] = parameters

        def fetchone(self):
            if empty_response:
                return (None,)
            return ('{"claims": [{"text": "结果", "citations": [{"source_id": 1, "quote": "Original evidence."}]}], "insufficient_evidence": false}',)

        def __enter__(self):
            return self

        def __exit__(self, *args):
            captured["cursor_closed"] = True

    @contextmanager
    def fake_connection(settings):
        try:
            yield SimpleNamespace(cursor=Cursor)
        finally:
            captured["connection_closed"] = True

    monkeypatch.setattr(generation, "connect", fake_connection)
    service = generation.GenerationService(Settings())
    if empty_response:
        with pytest.raises(ValueError, match="没有返回回答"):
            service.complete("test prompt")
    else:
        result = service.complete("test prompt")
        assert result.claims[0].text == "结果"
        assert result.claims[0].citations[0].quote == "Original evidence."
        assert result.insufficient_evidence is False

    response_format = json.loads(captured["parameters"][2])
    assert response_format["type"] == "json"
    assert response_format["schema"]["required"] == ["claims", "insufficient_evidence"]
    assert captured["connection_closed"]
    assert captured["cursor_closed"]


@pytest.mark.parametrize("value", ['[]', 'null', 'broken-json'])
def test_settings_rejects_invalid_scoring_config(monkeypatch, value):
    monkeypatch.setenv("RAG_SCORING_CONFIG", value)
    with pytest.raises(ValueError, match="RAG_SCORING_CONFIG"):
        Settings.from_env()


@pytest.mark.parametrize("fail_inside_connection", [False, True])
def test_connection_closes_after_use(monkeypatch, fail_inside_connection):
    from medical_rag.backend import connection

    captured = {}

    class Connection:
        def close(self):
            captured["closed"] = True

    def fake_connect(**options):
        captured["options"] = options
        return Connection()

    monkeypatch.setattr(connection.Path, "is_file", lambda path: False)
    monkeypatch.setenv("SNOWFLAKE_CONNECTION_NAME", "test-connection")
    monkeypatch.setattr(connection.snowflake.connector, "connect", fake_connect)

    if fail_inside_connection:
        with pytest.raises(RuntimeError):
            with connection.connect(Settings()):
                raise RuntimeError("测试业务调用失败")
    else:
        with connection.connect(Settings()):
            pass

    assert captured["closed"]
    assert captured["options"]["connection_name"] == "test-connection"
