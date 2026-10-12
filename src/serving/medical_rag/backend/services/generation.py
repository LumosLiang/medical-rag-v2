"""调用 AI_COMPLETE，返回结构化回答；问答与引用规则由 api.py 的 /ask 决定。"""
import json

from ..connection import connect
from ..models import Completion
from ..settings import Settings


class GenerationService:
    def __init__(self, settings: Settings):
        self.settings = settings

    def complete(self, prompt: str) -> Completion:
        # 约束模型返回的 JSON 字段；这不是数据库表的 schema。
        schema = {
            "type": "object",
            "properties": {
                "answer": {"type": "string"},
                "insufficient_evidence": {"type": "boolean"},
            },
            "required": ["answer", "insufficient_evidence"],
            "additionalProperties": False,
        }

        response_format = {
            "type": "json",
            "schema": schema,
        }
        response_format_json = json.dumps(response_format)

        # SQL 使用参数占位符，问题里的引号不会被当成 SQL 语法。
        # 官方：https://docs.snowflake.com/en/sql-reference/functions/ai_complete-structured-outputs
        sql = """
            SELECT AI_COMPLETE(
                %s,
                %s,
                OBJECT_CONSTRUCT('temperature', 0, 'max_tokens', 1200),
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
