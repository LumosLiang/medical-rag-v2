"""渲染每轮回答及来源卡片，不发请求、不修改会话。"""
import streamlit as st


def display_result(result: dict) -> None:
    if "answer" in result:
        st.subheader("回答")
        st.markdown(result["answer"])
    st.subheader("文献片段")
    if not result["sources"]:
        st.info("没有找到相关文献。")
    for source in result["sources"]:
        display_source(source, result.get("claims", []))


def display_source(source: dict, claims: list[dict]) -> None:
    start, end = source["page_start"], source["page_end"]
    pages = "页码未提供" if start is None else f"第 {start + 1} 页"
    if start is not None and end is not None and end > start:
        pages = f"第 {start + 1}–{end + 1} 页"
    label = f"[{source['citation_id']}] {source['relative_path']} · {pages}"
    if source["cited"]:
        label += " · 已引用"
    with st.expander(label, expanded=source["cited"]):
        # 每段摘录旁保留对应结论，便于核对“这句话依据哪里”。
        # 旧会话和 /search 没有 claims，仍可展示原始片段。
        for claim in claims:
            for citation in claim["citations"]:
                if citation["source_id"] == source["citation_id"]:
                    st.caption("对应结论：" + claim["text"])
                    st.text(citation["quote"])
        st.caption("完整检索片段")
        st.text(source["text"])


