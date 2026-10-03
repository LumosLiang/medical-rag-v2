from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse

from .settings import Settings
from .schemas import AnswerResponse, QueryRequest, SearchResponse
from .rag import answer_question
from .snowflake_access import SnowflakeAccess

app = FastAPI(title="Medical RAG", version="0.1.0")
settings = Settings.from_env()



# Depends(get_client) 会在收到请求时调用这个函数，把 client 传给路由。
# 创建 client 本身不连接 Snowflake；执行 search / complete 时才建立连接。
def get_client():
    return SnowflakeAccess(settings)


@app.exception_handler(NotImplementedError)
async def not_implemented(request: Request, error: NotImplementedError):
    return JSONResponse(status_code=501, content={"detail": str(error)})


@app.get("/healthz")
def health():
    # 不在探针中调用 Snowflake，避免持续触发查询。
    return {"status": "ok"}


# response_model 定义返回 JSON 的字段；QueryRequest 定义收到的 JSON 字段。
@app.post("/search", response_model=SearchResponse)
def search(request: QueryRequest, client=Depends(get_client)):
    # ===== 你来写：接收前端请求，调用检索，返回 JSON =====
    # FastAPI 已把 JSON 请求体变成 request，并校验 question 和 top_k。
    # 用 client.search(request) 检索，再返回 SearchResponse。
    # sources 来自检索结果，config_name 从 settings 取。
    raise NotImplementedError("你来写：实现 POST /search")
    # ===== 到这里 =====


@app.post("/ask", response_model=AnswerResponse)
def ask(request: QueryRequest, client=Depends(get_client)):
    # ===== 你来写：检索链路跑通后，再接回答生成 =====
    # answer_question(request, client, settings.config_name) 已提供引用处理。
    # 调用并返回结果；上游失败用 HTTPException 返回可读错误，不暴露凭据。
    raise NotImplementedError("先完成 /search，再实现 POST /ask")
    # ===== 到这里 =====
