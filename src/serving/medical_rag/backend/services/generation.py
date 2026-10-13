"""调用 AI_COMPLETE，返回结构化回答；问答与引用规则由 api.py 的 /ask 决定。"""
import json

from ..connection import connect
from ..models import Completion
from ..settings import Settings


class GenerationService:
    def __init__(self, settings: Settings):
        self.settings = settings

    def complete(self, prompt: str) -> Completion:

        # 先定义一条引用和一条结论，再组合成完整响应，避免嵌套难以阅读。
        # Schema 约束格式；原文是否存在、引用是否有效由 /ask 校验。
        citation_schema = {
            "type": "object",
            "properties": {
                "source_id": {"type": "integer"},
                "quote": {"type": "string"},
            },
            "required": ["source_id", "quote"],
            "additionalProperties": False,
        }
        claim_schema = {
            "type": "object",
            "properties": {
                "text": {"type": "string"},
                "citations": {"type": "array", "items": citation_schema},
            },
            "required": ["text", "citations"],
            "additionalProperties": False,
        }
        final_schema = {
            "type": "object",
            "properties": {
                "claims": {"type": "array", "items": claim_schema},
                "insufficient_evidence": {"type": "boolean"},
            },
            "required": ["claims", "insufficient_evidence"],
            "additionalProperties": False,
        }
        response_format = {
            "type": "json",
            "schema": final_schema,
        }
        response_format_json = json.dumps(response_format)

        # 官方：https://docs.snowflake.com/en/sql-reference/functions/ai_complete-structured-outputs
        # 原文摘录使输出变长；使用平台默认输出预算，不再沿用旧的 1200 上限。
        sql = """
            SELECT AI_COMPLETE(
                %s,
                %s,
                OBJECT_CONSTRUCT('temperature', 0),
                PARSE_JSON(%s)
            )
        """

        parameters = (
            self.settings.model,
            prompt,
            response_format_json,
        )

        with connect(self.settings) as connection:
            with connection.cursor() as cursor:
                cursor.execute(sql, parameters)
                row = cursor.fetchone()

        if row is None or row[0] is None:
            raise ValueError("AI_COMPLETE 没有返回回答")

        result = row[0]
        if isinstance(result, str):
            result = json.loads(result)
        # 将返回的字典变成 Completion，并检查字段和类型是否符合约定。
        return Completion.model_validate(result)
