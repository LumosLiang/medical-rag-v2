"""逐结论校验引用，生成展示标记；不判断证据是否在语义上支持结论。"""
import re

from fastapi import HTTPException

from .models import Claim, Completion, Source


def validate_claim_citations(claim: Claim, sources_by_id: dict[int, Source]) -> list[int]:
    # 即使模型声明证据不足，它给出的每条事实仍须通过相同校验。
    if not claim.text.strip() or not claim.citations:
        raise HTTPException(status_code=502, detail="本次回答有结论缺少证据引用，请重试。")
    if re.search(r"\[\d+\]", claim.text):
        raise HTTPException(status_code=502, detail="本次回答包含自行生成的引用标记，请重试。")

    claim_source_ids = []

    for citation in claim.citations:
        source = sources_by_id.get(citation.source_id)
        if source is None:
            raise HTTPException(status_code=502, detail="模型返回了不存在的引用编号，请重试。")

        # split() 拆开连续空白，join() 用单空格接回；只容忍换行、空格的差别。
        # 不去掉标点或改写数字，避免把 -6.1 / 6.1、≥ / ≤ 当作相同证据。
        normalized_quote = " ".join(citation.quote.split())
        normalized_source = " ".join(source.text.split())
        if not normalized_quote or normalized_quote not in normalized_source:
            raise HTTPException(status_code=502, detail="引用摘录未能在对应文献片段中找到，请重试。")

        # 同一结论的重复引用只保留一次编号，保留首次出现顺序。
        if citation.source_id not in claim_source_ids:
            claim_source_ids.append(citation.source_id)

    return claim_source_ids


def render_cited_answer(completion: Completion, sources: list[Source]) -> str:
    if not completion.claims and not completion.insufficient_evidence:
        raise HTTPException(status_code=502, detail="模型没有返回可核验的结论，请重试。")

    # 根据来源编号查找原文。文件、页码和 chunk_id 始终来自检索结果。
    sources_by_id = {}
    for source in sources:
        sources_by_id[source.citation_id] = source

    # cited_ids 收集通过校验的来源，全部结论通过后才标记 Source。
    cited_ids = set()

    answer_parts = []

    for claim in completion.claims:
        claim_source_ids = validate_claim_citations(claim, sources_by_id)
        cited_ids.update(claim_source_ids)

        # 将已校验、去重的来源编号转换为前端展示的 [1]、[2] 等标记。
        markers = []
        for source_id in claim_source_ids:
            markers.append(f"[{source_id}]")

        # 引用编号由后端拼接，模型只提供结论和证据摘录。
        answer_parts.append(claim.text.strip() + " " + " ".join(markers))

    if completion.insufficient_evidence:
        answer_parts.append("现有检索证据不足以完整回答这个问题。")

    # 标记哪些检索片段被模型引用过
    for source in sources:
        source.cited = source.citation_id in cited_ids

    return "\n\n".join(answer_parts)
