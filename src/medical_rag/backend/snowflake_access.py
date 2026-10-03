import json
import os
from contextlib import contextmanager
from pathlib import Path

import snowflake.connector
from snowflake.core import Root

from .settings import Settings
from .schemas import Completion, QueryRequest, Source


# @contextmanager 让这个函数可以用 with：进入时建立连接，退出时关闭。
@contextmanager
def connect(settings: Settings):
    options = dict(
        database=settings.database, schema=settings.schema,
        warehouse=settings.warehouse, login_timeout=30,
        network_timeout=120, session_parameters={
            "QUERY_TAG": "medical-rag-v2-app", "STATEMENT_TIMEOUT_IN_SECONDS": 120,
        },
    )
    token_file = Path("/snowflake/session/token")
    if token_file.is_file():
        # SPCS 会轮换 token，每次新建连接时重新读文件。
        options.update(account=os.environ["SNOWFLAKE_ACCOUNT"],
                       host=os.environ["SNOWFLAKE_HOST"], authenticator="oauth",
                       token=token_file.read_text().strip())
    elif os.getenv("SNOWFLAKE_CONNECTION_NAME"):
        options.update(connection_name=os.environ["SNOWFLAKE_CONNECTION_NAME"],
                       role=os.getenv("SNOWFLAKE_ROLE", "MEDRAG_ADMIN"))
    else:
        options.update(account=os.environ["SNOWFLAKE_ACCOUNT"],
                       user=os.environ["SNOWFLAKE_USER"],
                       role=os.getenv("SNOWFLAKE_ROLE", "MEDRAG_ADMIN"),
                       authenticator="PROGRAMMATIC_ACCESS_TOKEN",
                       token=os.environ["SNOWFLAKE_TOKEN"])
    connection = snowflake.connector.connect(**options)
    try:
        # yield 把连接交给 with 里的代码；用完后回来执行 finally。
        yield connection
    finally:
        connection.close()


class SnowflakeAccess:
    def __init__(self, settings: Settings):
        self.settings = settings

    def search(self, request: QueryRequest) -> list[Source]:
        # ===== 你来写：Cortex Search Python API =====
        # 1. with connect(self.settings) as connection: 打开连接。
        # 2. Root(connection) → databases → schemas → cortex_search_services 取服务。
        # 3. service.search 接收 query、columns、limit；指定文件时加 filter。
        # 4. 把返回的 results 转成 list[Source]，citation_id 从 1 开始。
        # columns: CHUNK_ID / RELATIVE_PATH / PAGE_START / PAGE_END / CHUNK_TEXT。
        # 配置名和服务名可从 self.settings 取，不在这里写账号和凭据。
        raise NotImplementedError("你来写：调用 Cortex Search 并返回 Source 列表")
        # ===== 到这里 =====

    def complete(self, prompt: str) -> Completion:
        # 这里的 schema 是模型回答的 JSON 格式，不是 Snowflake 的数据库 schema。
        # 要求模型给出 answer 和 insufficient_evidence，方便后面检查引用。
        schema = {"type": "object", "properties": {
            "answer": {"type": "string"},
            "insufficient_evidence": {"type": "boolean"},
        }, "required": ["answer", "insufficient_evidence"],
            "additionalProperties": False}
        with connect(self.settings) as connection, connection.cursor() as cursor:
            # %s 是参数占位符，模型名、提示词和格式通过下方元组传入。
            # 不用拼接 SQL，避免问题文本里的引号破坏语句。
            cursor.execute(
                "SELECT AI_COMPLETE(%s, %s, "
                "OBJECT_CONSTRUCT('temperature', 0, 'max_tokens', 1200), "
                "PARSE_JSON(%s))",
                (self.settings.model, prompt, json.dumps(schema)),
            )
            result = cursor.fetchone()[0]
        if isinstance(result, str):
            result = json.loads(result)
        # 将返回的字典变成 Completion，并检查字段和类型是否符合约定。
        return Completion.model_validate(result)
