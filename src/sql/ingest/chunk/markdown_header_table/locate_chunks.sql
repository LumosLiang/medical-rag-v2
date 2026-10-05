-- 原生 header splitter 不返回原文位置；这里只补定位、页码和章节路径，不切正文。
USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

CREATE OR REPLACE FUNCTION CORE.LOCATE_MARKDOWN_CHUNKS(document OBJECT, candidates ARRAY)
RETURNS TABLE (piece_index INTEGER, chunk_text VARCHAR, section_path VARCHAR,
              page_start INTEGER, page_end INTEGER, location_exact BOOLEAN)
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
HANDLER = 'LocateChunks'
AS
$$
import bisect
import re


class LocateChunks:
    def process(self, document, candidates):
        text = document['text']
        headings, paths, stack = [], [], ['', '', '']
        # 只提取章节元数据。正文切分本身仍使用 Snowflake 的 header splitter。
        # 扫全文而不是每个 TEXT 段重新起算，可保留被表格隔开的上级标题。
        for match in re.finditer(r'^(#{1,3})[ \t]+(.+)$', text, re.M):
            level = len(match.group(1)) - 1
            stack[level] = match.group(2).strip()
            stack[level + 1:] = [''] * (2 - level)
            headings.append(match.start())
            paths.append(stack.copy())
        previous_start = {}
        for index, candidate in enumerate(candidates or []):
            if candidate['kind'] == 'TABLE':
                start, end = candidate['start'], candidate['end']
                exact = True
            else:
                span_start, span_end = candidate['span_start'], candidate['span_end']
                # overlap 的下一块可能在上一块结束之前；从“上次起点 + 1”搜索。
                key = candidate['span_index']
                search_start = previous_start.get(key, span_start - 1) + 1
                start = text.find(candidate['text'], search_start, span_end)
                exact = start >= 0
                if exact:
                    end = start + len(candidate['text'])
                    previous_start[key] = start
                else:
                    # 不借用前一块的页码；扩大到所属 TEXT 段，避免给出错误的窄页码。
                    start, end = span_start, span_end
            heading_index = bisect.bisect_right(headings, start) - 1
            current = paths[heading_index].copy() if heading_index >= 0 else ['', '', '']
            if not exact:
                # 无法定位时，原生 headers 补充本段已知标题；新 h2 会清除旧 h3。
                for level in range(3):
                    value = (candidate.get('headers') or {}).get(f'h{level + 1}')
                    if value is not None:
                        current[level] = value
                        current[level + 1:] = [''] * (2 - level)
            pages = [page['page'] for page in document['pages']
                     if page['start'] < end and page['end'] > start]
            yield (index, candidate['text'], ' > '.join(h for h in current if h) or None,
                   min(pages) if pages else None, max(pages) if pages else None, exact)
$$;
