import logging

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse

from .citations import render_cited_answer
from .prompts import build_answer_prompt
from .settings import Settings
from .models import AnswerResponse, QueryRequest, SearchResponse
from .services.retrieval import RetrievalService
from .services.generation import GenerationService

app = FastAPI(title="Medical RAG backend", version="0.1.0")

# 从环境变量读取配置，或使用默认值；不直接修改配置对象。
settings = Settings.from_env()
logger = logging.getLogger(__name__)


# FastAPI 收到请求时调用这些函数，把返回的对象传给路由参数。
def get_retrieval_service():
    return RetrievalService(settings)


def get_generation_service():
    return GenerationService(settings)


@app.exception_handler(Exception)
async def unexpected_error(request: Request, error: Exception):
    # 详细错误留在服务日志，不把连接信息或上游异常原文返回给前端。
    logger.error("后端请求失败", exc_info=error)
    return JSONResponse(
        status_code=500,
        content={"detail": "后端处理失败，请查看服务日志。"},
    )


@app.get("/healthz")
def health():
    # 不在探针中调用 Snowflake，避免持续触发查询。
    return {"status": "ok"}


# response_model 定义返回 JSON 的字段；QueryRequest 定义收到的 JSON 字段。
@app.post("/search", response_model=SearchResponse)
def search(
    request: QueryRequest,
    retrieval_service=Depends(get_retrieval_service),
):

    sources = retrieval_service.search(request)
    return SearchResponse(
        sources=sources,
        config_name=settings.config_name,
    )


@app.post("/ask", response_model=AnswerResponse)
def ask(
    request: QueryRequest,
    retrieval_service=Depends(get_retrieval_service),
    generation_service=Depends(get_generation_service),
):
    sources = retrieval_service.search(request)
    if not sources:
        return AnswerResponse(
            answer="没有找到相关文献，暂时无法回答。",
            insufficient_evidence=True,
            sources=[],
            config_name=settings.config_name,
        )

    prompt = build_answer_prompt(request.question, sources)

    try:
        completion = generation_service.complete(prompt)
    except ValueError as error:
        # 格式或类型不合法时不把模型原始输出透传给用户。
        raise HTTPException(
            status_code=502,
            detail="未获得可校验的生成结果，请重试。",
        ) from error

    answer = render_cited_answer(completion, sources)

    # 上述检查证明摘录来自检索原文，不证明原文在语义上支持结论。
    return AnswerResponse(
        answer=answer,
        claims=completion.claims,
        insufficient_evidence=completion.insufficient_evidence,
        sources=sources,
        config_name=settings.config_name,
    )
