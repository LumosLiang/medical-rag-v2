"""只管理 Snowflake 连接与凭据，不执行检索或生成。"""
import os
from contextlib import contextmanager
from pathlib import Path

import snowflake.connector

from .settings import Settings


# @contextmanager 让这个函数可以用 with：进入时建立连接，退出时关闭。
@contextmanager
def connect(settings: Settings):
    options = {
        "database": settings.database,
        "schema": settings.schema,
        "warehouse": settings.warehouse,
        "login_timeout": 30,
        "network_timeout": 120,
        "session_parameters": {
            "QUERY_TAG": "medical-rag-v2-app",
            "STATEMENT_TIMEOUT_IN_SECONDS": 120,
        },
    }

    token_file = Path("/snowflake/session/token")
    connection_name = os.getenv("SNOWFLAKE_CONNECTION_NAME")

    if token_file.is_file():
        # SPCS 会轮换 token，每次新建连接时重新读文件。
        options["account"] = os.environ["SNOWFLAKE_ACCOUNT"]
        options["host"] = os.environ["SNOWFLAKE_HOST"]
        options["authenticator"] = "oauth"
        options["token"] = token_file.read_text().strip()
    elif connection_name:
        # 本地使用已配置的命名连接，不在代码中保存凭据。
        options["connection_name"] = connection_name
        options["role"] = os.getenv("SNOWFLAKE_ROLE", "MEDRAG_ADMIN")
    else:
        # 本地通过环境变量提供 PAT。
        options["account"] = os.environ["SNOWFLAKE_ACCOUNT"]
        options["user"] = os.environ["SNOWFLAKE_USER"]
        options["role"] = os.getenv("SNOWFLAKE_ROLE", "MEDRAG_ADMIN")
        options["authenticator"] = "PROGRAMMATIC_ACCESS_TOKEN"
        options["token"] = os.environ["SNOWFLAKE_TOKEN"]

    # **options 将字典展开成 connect 的具名参数。
    connection = snowflake.connector.connect(**options)
    try:
        # yield 把连接交给 with 里的代码；用完后回来执行 finally。
        yield connection
    finally:
        connection.close()
