import os

import httpx
import streamlit as st

st.set_page_config(page_title="医学文献检索", page_icon="📚", layout="wide")
st.title("医学文献检索")
st.caption("根据文献回答问题，查看每个引用对应的原文。")
backend_url = os.getenv("BACKEND_URL", "http://localhost:8000").rstrip("/")


def send_query(payload: dict, generate_answer: bool) -> dict:
    # ===== 你来写：前端向 FastAPI 发 HTTP 请求 =====
    # 根据 generate_answer 选择 /ask 或 /search。
    # 用 httpx.post，传 json=payload 和 timeout；检查状态码，返回 response.json()。
    raise NotImplementedError("你来写：从前端发出查询请求")
    # ===== 到这里 =====


def save_result(result: dict) -> None:
    # ===== 你来写：Streamlit 上下文管理 =====
    # Streamlit 每次交互会重新执行脚本；把 result 保存到 session_state，
    # 页面重跑时才能继续显示本次结果。下面展示区使用 session_state['result']。
    raise NotImplementedError("你来写：保存当前会话的查询结果")
    # ===== 到这里 =====


with st.form("question_form"):
    question = st.text_area("你想了解什么？", placeholder="例如：这些研究如何评估治疗效果？")
    with st.expander("检索设置"):
        top_k = st.slider("检索片段数", min_value=1, max_value=10, value=5)
        relative_path = st.text_input("限定文献（可选）", placeholder="PMC1234567.pdf")
    generate_answer = st.checkbox("生成带引用的回答", value=False)
    submitted = st.form_submit_button("查询", type="primary")

if submitted:
    if not question.strip():
        st.warning("请先输入问题。")
    else:
        payload = {"question": question.strip(), "top_k": top_k,
                   "relative_path": relative_path.strip() or None}
        try:
            with st.spinner("正在查询文献…"):
                result = send_query(payload, generate_answer)
                save_result(result)
        except NotImplementedError as error:
            st.info(str(error))
        except httpx.HTTPStatusError as error:
            st.session_state.pop("result", None)
            try:
                detail = error.response.json().get("detail", "查询失败，请稍后重试。")
            except ValueError:
                detail = "查询失败，请稍后重试。"
            st.error(detail if isinstance(detail, str) else "请检查问题和检索参数。")
        except httpx.RequestError:
            st.session_state.pop("result", None)
            st.error("暂时无法连接检索服务，请稍后重试。")

def load_result() -> dict | None:
    # ===== 你来写：页面重跑时读取当前会话的结果 =====
    # 与 save_result 使用同一个 key。首次打开没有结果时返回 None。
    return None
    # ===== 到这里 =====


if result := load_result():
    if "answer" in result:
        st.subheader("回答")
        st.markdown(result["answer"])
    st.subheader("文献片段")
    if not result["sources"]:
        st.info("没有找到相关文献。")
    for source in result["sources"]:
        start, end = source["page_start"], source["page_end"]
        pages = "页码未提供" if start is None else f"第 {start + 1} 页"
        if start is not None and end is not None and end > start:
            pages = f"第 {start + 1}–{end + 1} 页"
        label = f"[{source['citation_id']}] {source['relative_path']} · {pages}"
        if source["cited"]:
            label += " · 已引用"
        with st.expander(label, expanded=source["cited"]):
            st.text(source["text"])
