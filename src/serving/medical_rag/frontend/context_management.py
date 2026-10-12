"""管理当前 Streamlit 会话的记录，不负责调用模型或永久保存历史。"""
import streamlit as st


MAX_HISTORY_TURNS = 20
CONTEXT_TURNS = 5


def initialize_context() -> None:
    # Streamlit 每次交互会重跑脚本；已有记录不能重新初始化成空列表。
    if "turns" not in st.session_state:
        st.session_state["turns"] = []


def save_result(question: str, result: dict) -> None:
    initialize_context()
    st.session_state["result"] = result

    # /search 只有检索片段，不作为一轮问答加入对话历史。
    if "answer" not in result:
        return

    # 一轮是一个问题及其回答。保留本轮来源，避免 [1] 混到其他轮的引用。
    turn = {
        "question": question,
        "result": result,
    }
    turns = st.session_state["turns"]
    turns.append(turn)

    # 超过上限时从头删除最早的一轮。这是按时间保留，不是 LRU。
    while len(turns) > MAX_HISTORY_TURNS:
        turns.pop(0)


def load_latest_result() -> dict | None:
    return st.session_state.get("result")


def get_turns() -> list[dict]:
    initialize_context()
    return st.session_state["turns"]


def get_recent_messages() -> list[dict]:
    # 最近 5 轮只是初始选择，不是 token 上限。
    # 只返回问答文本，不把以前的检索片段当作新问题的证据。
    # 以后做问题改写时使用；当前还没有发送给后端或模型。
    turns = get_turns()
    recent_turns = turns[-CONTEXT_TURNS:]
    messages = []
    for turn in recent_turns:
        user_message = {
            "role": "user",
            "content": turn["question"],
        }
        assistant_message = {
            "role": "assistant",
            "content": turn["result"]["answer"],
        }
        messages.append(user_message)
        messages.append(assistant_message)
    return messages


def clear_context() -> None:
    st.session_state["turns"] = []
    st.session_state.pop("result", None)
