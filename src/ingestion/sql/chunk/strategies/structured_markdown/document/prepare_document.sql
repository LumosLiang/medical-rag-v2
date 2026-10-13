-- 在既有规范化全文上清理明确噪声，重新计算页范围，并标记需要完整保留的摘要。
-- 不猜测缺失的标题，不按引用数字删正文。过滤规则保守，无法识别的内容仍保留。
USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

CREATE OR REPLACE FUNCTION CORE.CLEAN_MARKDOWN_DOCUMENT(document OBJECT, options OBJECT)
RETURNS OBJECT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
HANDLER = 'clean'
AS
$$
import re

HEADING = re.compile(r'^(#{1,6})\s+(.+)$')
REFERENCES = re.compile(r'^(?:\d+[.\s]+)?(?:references|bibliography|literature cited)$', re.I)
ABSTRACT = re.compile(r'^(?:\d+[.\s]+)?(?:abstract|summary)$', re.I)
STRUCTURED_LABELS = {'background', 'objectives', 'objective', 'methods', 'method',
                     'results', 'conclusions', 'conclusion', 'purpose', 'aim'}
PUBLICATION_NOISE = re.compile(
    r'^(?:©|copyright\b|this (?:article|work) is (?:licensed|distributed)\b|'
    r'creative commons\b|https?://creativecommons\.org/|'
    r'permission (?:to|for)\b|all rights reserved\b)', re.I)


def label(line):
    match = HEADING.match(line.strip())
    if match:
        return len(match.group(1)), match.group(2).strip().strip('*').strip()
    # 独占一行的粗体 Abstract / References 也视为边界；普通句子不匹配。
    return 1, line.strip().strip('*').strip()


def mask_noise(source, options):
    lines = source.splitlines(keepends=True)
    offset = 0
    reference_level = None
    keep = list(source)
    removed_references = 0
    removed_publication = 0
    for line in lines:
        level, title = label(line)
        is_heading = bool(HEADING.match(line.strip()))
        # References 后遇到同级或上级新章节即恢复，不吞掉明确的附录章节。
        if reference_level is not None and is_heading and level <= reference_level:
            reference_level = None
        if options.get('drop_reference_sections') and REFERENCES.fullmatch(title):
            reference_level = level
        drop_reference = reference_level is not None
        drop_publication = options.get('drop_publication_noise') and PUBLICATION_NOISE.match(line.strip())
        if drop_reference or drop_publication:
            if drop_reference:
                removed_references += 1
            else:
                removed_publication += 1
            # 先等长遮掉行，再按原来的页范围取片段，保证没有内容串到相邻页。
            for index in range(offset, offset + len(line)):
                if keep[index] not in '\r\n':
                    keep[index] = ' '
        offset += len(line)
    masked = ''.join(keep)
    return masked, removed_references, removed_publication


def rebuild_pages(masked, original_pages):
    parts = []
    pages = []
    new_offset = 0
    for page in original_pages:
        page_text = masked[page['start']:page['end']]
        page_text = '\n'.join(line.rstrip() for line in page_text.split('\n') if line.strip())
        if not page_text:
            continue
        if parts:
            new_offset += 1
        pages.append({'page': page['page'], 'start': new_offset, 'end': new_offset + len(page_text)})
        parts.append(page_text)
        new_offset += len(page_text)
    text = '\n'.join(parts)
    return text, pages


def collect_headings(text):
    headings = []
    offset = 0
    for line in text.splitlines(keepends=True):
        level, title = label(line)
        if HEADING.match(line.strip()) or ABSTRACT.fullmatch(title):
            headings.append((offset, level, title))
        offset += len(line)
    return headings


def find_heading_abstract(text, pages):
    # 只选论文前部的一段摘要，排除正文 Summary 和重复 Abstract 页眉。
    headings = collect_headings(text)
    front_end = pages[min(2, len(pages) - 1)]['end'] if pages else 0
    candidates = []
    explicit = []
    for index, item in enumerate(headings):
        if item[0] < front_end and ABSTRACT.fullmatch(item[2]):
            candidates.append((index, item))
            if item[2].lower().endswith('abstract'):
                explicit.append((index, item))
    selected = explicit or candidates
    if not selected:
        return []

    index, (start, level, title) = selected[0]
    end = len(text)
    following = headings[index + 1:]
    structured_headings = []
    for item in following:
        if item[2].lower() not in STRUCTURED_LABELS:
            break
        structured_headings.append(item)
    # 必须确认连续小标题含 Conclusions，才将它们全部保留在摘要中。
    has_conclusion = any(item[2].lower().startswith('conclusion') for item in structured_headings)
    if has_conclusion and structured_headings[-1][0] - start < 12000:
        following = following[len(structured_headings):]
    if following:
        end = following[0][0]
    # 关键词之后可能是缩略词表或没有 Markdown 标题的正文，不能纳入摘要。
    keyword = re.search(r'^(?:#{1,6}\s+)?(?:\*\*)?Key\s*words?\s*[:：]',
                        text[start:end], re.M | re.I)
    if keyword:
        end = start + keyword.start()
    return [{'start': start, 'end': end}]


def find_labelled_abstract(text, pages):
    # 无 Abstract 标题时，只在前两页查找明确的方法、结果和结论标签。
    first_pages_end = pages[min(1, len(pages) - 1)]['end'] if pages else 0
    labels = list(re.finditer(
        r'^(?:#{1,6}\s+)?(?:\*\*)?(Background|Introduction|Objectives?|Purpose|Methods?|Results|Conclusions?)[.:]\s*',
        text[:first_pages_end], re.M | re.I))
    names = {match.group(1).lower().rstrip('s') for match in labels}
    if not {'method', 'result', 'conclusion'}.issubset(names):
        return []
    conclusion = next(match for match in labels if match.group(1).lower().startswith('conclusion'))
    end = text.find('\n', conclusion.end())
    end = len(text) if end < 0 else end
    return [{'start': labels[0].start(), 'end': end}]


def clean(document, options):
    options = options or {}
    if not options:
        return document

    # 清理、坐标重建、摘要识别依次执行；摘要位置必须使用清理后的全文。
    masked, removed_references, removed_publication = mask_noise(document['text'], options)
    text, pages = rebuild_pages(masked, document['pages'])
    abstracts = []
    if options.get('preserve_abstract'):
        abstracts = find_heading_abstract(text, pages)
        if not abstracts:
            abstracts = find_labelled_abstract(text, pages)
    return {'text': text, 'pages': pages, 'abstracts': abstracts,
            'removed_reference_lines': removed_references,
            'removed_publication_lines': removed_publication}
$$;
