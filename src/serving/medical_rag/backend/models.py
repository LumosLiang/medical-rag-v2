# 这些类定义前后端交换的 JSON 格式；Pydantic 会检查字段类型和取值。
from pydantic import BaseModel, Field, field_validator


class QueryRequest(BaseModel):
    question: str = Field(min_length=1, max_length=2000)
    top_k: int = Field(default=5, ge=1, le=10)
    relative_path: str | None = Field(default=None, max_length=255)

    @field_validator("question")
    @classmethod
    def strip_question(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("问题不能为空")
        return value


class Source(BaseModel):
    citation_id: int
    # 数据库块的标识，用于追溯来源；不是本次回答中的 [1] 编号。
    chunk_id: str
    relative_path: str
    page_start: int | None = None
    page_end: int | None = None
    text: str
    cited: bool = False


class SearchResponse(BaseModel):
    sources: list[Source]
    config_name: str


class AnswerResponse(SearchResponse):
    answer: str
    insufficient_evidence: bool


class Completion(BaseModel):
    answer: str = Field(min_length=1)
    insufficient_evidence: bool
