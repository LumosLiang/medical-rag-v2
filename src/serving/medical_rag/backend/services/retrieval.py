"""从 Cortex Search 检索原文，并转换为应用的 Source。"""
from snowflake.core import Root

from ..connection import connect
from ..models import QueryRequest, Source
from ..settings import Settings


class RetrievalService:
    def __init__(self, settings: Settings):
        self.settings = settings

    def search(self, request: QueryRequest) -> list[Source]:
        with connect(self.settings) as connection:
            # 一层一层选择对象，最后得到 Cortex Search 服务。
            root = Root(connection)
            database = root.databases[self.settings.database]
            schema = database.schemas[self.settings.schema]
            service = schema.cortex_search_services[self.settings.search_service]

            columns = [
                "CHUNK_ID",
                "RELATIVE_PATH",
                "PAGE_START",
                "PAGE_END",
                "CHUNK_TEXT",
            ]

            # @eq 是 Cortex Search 的等值筛选语法，不是普通的字段字典。
            search_filter = None
            if request.relative_path is not None:
                search_filter = {
                    "@eq": {"RELATIVE_PATH": request.relative_path}
                }

            # 官方：https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/query-cortex-search-service
            # 左边是 Snowflake API 参数；右边是我们自己的请求字段。
            response = service.search(
                query=request.question,
                columns=columns,
                limit=request.top_k,
                scoring_config=self.settings.scoring_config,
                filter=search_filter,
            )

            # SDK 返回的是响应对象，实际的行列表在 response.results 中。
            result_rows = response.results
            sources = []
            for citation_id, row in enumerate(result_rows, start=1):
                # chunk_id 标识数据库中的块；citation_id 只给本次回答编号。
                # 文件、页码和原文来自检索结果，不由生成模型填写。
                # citation_id 起始为 1，便于模型引用
                source = Source(
                    citation_id=citation_id,
                    chunk_id=row["CHUNK_ID"],
                    relative_path=row["RELATIVE_PATH"],
                    page_start=row["PAGE_START"],
                    page_end=row["PAGE_END"],
                    text=row["CHUNK_TEXT"],
                )
                sources.append(source)

        return sources
