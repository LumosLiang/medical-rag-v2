import os

import httpx
import streamlit as st

from medical_rag.frontend.views import display_result
from medical_rag.frontend.context_management import (
    clear_context,
    get_turns,
    initialize_context,
    load_latest_result,
    save_result,
)

st.set_page_config(page_title="医学文献检索", page_icon="📚", layout="wide")
st.title("医学文献检索")
st.caption("根据文献回答问题，查看每个引用对应的原文。")
backend_url = os.getenv("BACKEND_URL", "http://localhost:8000").rstrip("/")


def send_query(payload: dict, generate_answer: bool) -> dict:

    if generate_answer:
        endpoint = f"{backend_url}/ask"
    else:
        endpoint = f"{backend_url}/search"

    # 检索后还要生成回答；读取响应的等待时间比连接时间长。
    timeout = httpx.Timeout(180, connect=10)
    response = httpx.post(endpoint, json=payload, timeout=timeout)
    response.raise_for_status()
    return response.json()


initialize_context()
if st.button("清空对话"):
    clear_context()

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
                save_result(question.strip(), result)
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


# 每轮回答和来源放在一起展示；编号 [1] 只对应所在轮的片段。
for turn in get_turns():
    with st.chat_message("user"):
        st.write(turn["question"])
    with st.chat_message("assistant"):
        display_result(turn["result"])

# 单独检索不属于对话历史，只显示最近一次检索结果。
latest_result = load_latest_result()
if latest_result is not None:
    if "answer" not in latest_result:
        display_result(latest_result)
