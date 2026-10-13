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


class Citation(BaseModel):
    source_id: int = Field(strict=True)
    quote: str = Field(min_length=1)


class Claim(BaseModel):
    text: str = Field(min_length=1)
    citations: list[Citation]


class AnswerResponse(SearchResponse):
    # answer 由后端根据通过校验的 claims 拼接，供展示和会话历史使用。
    answer: str
    claims: list[Claim] = Field(default_factory=list)
    insufficient_evidence: bool


class Completion(BaseModel):
    # 模型只输出结论和证据，不自行生成文件信息或 [1] 这样的展示编号。
    claims: list[Claim]
    insufficient_evidence: bool
