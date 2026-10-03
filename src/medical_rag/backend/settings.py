"""本机配置从环境读取；SPCS 注入连接凭据，不把账号或密钥放进代码。"""
import os
from dataclasses import dataclass


# dataclass 自动生成初始化方法；frozen=True 表示创建后不直接修改配置。
@dataclass(frozen=True)
class Settings:
    database: str = "MEDRAG"
    schema: str = "CORE"
    warehouse: str = "MEDICAL_RAG_INDEX_WH"
    config_name: str = "recursive_once_1200_200"
    model: str = "llama3.3-70b"

    # property 让 search_service 像字段一样读取，服务名根据配置名计算。
    @property
    def search_service(self) -> str:
        return "MEDICAL_CHUNKS_" + self.config_name.upper()

    @classmethod
    def from_env(cls):
        return cls(
            database=os.getenv("SNOWFLAKE_DATABASE", cls.database),
            schema=os.getenv("SNOWFLAKE_SCHEMA", cls.schema),
            warehouse=os.getenv("SNOWFLAKE_WAREHOUSE", cls.warehouse),
            config_name=os.getenv("RAG_CONFIG_NAME", cls.config_name),
            model=os.getenv("RAG_MODEL", cls.model),
        )
