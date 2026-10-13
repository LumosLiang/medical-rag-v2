-- 在 TEXT 段中隔离摘要：摘要作为完整候选，其他正文仍交给原生 header splitter。
-- 若摘要中含表格，表格由既有元素提取器独立处理；不会把表格再重复写进摘要。
USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

CREATE OR REPLACE FUNCTION CORE.SPLIT_ABSTRACT_SPANS(span_text VARCHAR, span_start INTEGER, abstracts ARRAY)
RETURNS TABLE (piece_index INTEGER, span_type VARCHAR, source_start INTEGER,
              source_end INTEGER, piece_text VARCHAR)
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
HANDLER = 'SplitAbstractSpans'
AS
$$
class SplitAbstractSpans:
    def process(self, span_text, span_start, abstracts):
        end = span_start + len(span_text)
        cursor = span_start
        index = 0
        for abstract in sorted(abstracts or [], key=lambda item: item['start']):
            left = max(span_start, abstract['start'])
            right = min(end, abstract['end'])
            if left >= right:
                continue
            if left > cursor:
                value = span_text[cursor - span_start:left - span_start]
                if value.strip():
                    yield (index, 'TEXT', cursor, left, value)
                    index += 1
            value = span_text[left - span_start:right - span_start]
            if value.strip():
                yield (index, 'ABSTRACT', left, right, value)
                index += 1
            cursor = right
        if cursor < end:
            value = span_text[cursor - span_start:]
            if value.strip():
                yield (index, 'TEXT', cursor, end, value)
$$;
