"""本机配置从环境读取；SPCS 注入连接凭据，不把账号或密钥放进代码。"""
import json
import os
from dataclasses import dataclass, field


def default_scoring_config() -> dict:
    # 每次调用都创建独立字典，避免多个配置对象共用可修改的权重。
    return {
        "weights": {
            "texts": 1,
            "vectors": 1,
            "reranker": 3,
        },
        "functions": {
            "text_boosts": [
                {"column": "chunk_text", "weight": 1},
                {"column": "section_path", "weight": 3},
            ],
        },
    }


# dataclass 自动生成初始化方法；frozen=True 表示创建后不直接修改配置。
@dataclass(frozen=True)
class Settings:
    database: str = "MEDRAG"
    schema: str = "CORE"
    warehouse: str = "MEDICAL_RAG_INDEX_WH"
    # config_name 标识块来源；同一批块可以建立多个不同的搜索服务。
    config_name: str = "markdown_header_table_1200_200"
    search_service: str = "MEDICAL_CHUNKS_MARKDOWN_MULTI_INDEX_1200_200"
    model: str = "claude-opus-5"
    # 最佳历史实验请求：整体关键词/向量/重排 1:1:3，正文/章节关键词 1:3。
    # 权重必须随 search 请求发送，不是服务定义自带的默认值。
    scoring_config: dict = field(default_factory=default_scoring_config)

    @classmethod
    def from_env(cls):
        defaults = cls()

        database = os.getenv("SNOWFLAKE_DATABASE", defaults.database)
        schema = os.getenv("SNOWFLAKE_SCHEMA", defaults.schema)
        warehouse = os.getenv("SNOWFLAKE_WAREHOUSE", defaults.warehouse)
        config_name = os.getenv("RAG_CONFIG_NAME", defaults.config_name)
        search_service = os.getenv("RAG_SEARCH_SERVICE", defaults.search_service)
        model = os.getenv("RAG_MODEL", defaults.model)

        # 未设置环境变量时用默认权重；设置时把 JSON 文本解析成字典。
        scoring_config = defaults.scoring_config
        scoring_json = os.getenv("RAG_SCORING_CONFIG")
        if scoring_json is not None:
            try:
                scoring_config = json.loads(scoring_json)
            except json.JSONDecodeError as error:
                raise ValueError("RAG_SCORING_CONFIG 必须是有效的 JSON 对象") from error
            if not isinstance(scoring_config, dict):
                raise ValueError("RAG_SCORING_CONFIG 必须是 JSON 对象，不能是列表或标量")

        return cls(
            database=database,
            schema=schema,
            warehouse=warehouse,
            config_name=config_name,
            search_service=search_service,
            model=model,
            scoring_config=scoring_config,
        )
