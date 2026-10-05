-- 只识别结构和原文位置，不做 token 计算，也不改变表格单元格内容。
-- 正文与表格按原顺序输出；SQL 后续分别交给标题 splitter 和表格分组器。
USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

CREATE OR REPLACE FUNCTION CORE.SPLIT_TABLE_SPANS(document_text VARCHAR)
RETURNS TABLE (span_index INTEGER, span_type VARCHAR, source_start INTEGER,
              source_end INTEGER, span_text VARCHAR, table_data OBJECT)
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
HANDLER = 'SplitTableSpans'
AS
$$
import re

CAPTION = re.compile(r'^\s*(?:#{1,6}\s+)?\*{0,2}Table\s+(?:[A-Z]?\d+|[IVX]+)\b', re.I)
SEPARATOR_CELL = re.compile(r'^:?-{3,}:?$')


def cells(line):
    # 不把转义的 \| 当成列分隔符。
    return [cell.strip() for cell in re.split(r'(?<!\\)\|', line.strip().strip('|'))]


def pipe_row(line):
    return line.lstrip().startswith('|') and len(cells(line)) > 1


def separator(line):
    return pipe_row(line) and all(SEPARATOR_CELL.fullmatch(cell) for cell in cells(line))


def table_start(lines, index):
    return index + 1 < len(lines) and pipe_row(lines[index]) and separator(lines[index + 1])


def make_table(lines, offsets, first, last, caption):
    header_end = first + 2
    # 医学表格常有多层表头：分隔行后，首列空白的行仍是表头。
    while header_end < last and not cells(lines[header_end])[0]:
        header_end += 1
    prefix_lines = ([caption] if caption else []) + lines[first:header_end]
    rows = []
    group = None
    for index in range(header_end, last):
        values = cells(lines[index])
        row = {'text': lines[index], 'start': offsets[index],
               'end': offsets[index] + len(lines[index])}
        if values[0] and not any(values[1:]):
            group = len(rows)  # 只有第一格有字的行，是下一组数据的标签。
        row['group'] = group
        rows.append(row)
    return {'prefix': '\n'.join(prefix_lines), 'rows': rows,
            'header_start': offsets[first],
            'header_end': offsets[header_end - 1] + len(lines[header_end - 1]),
            'caption': caption}


class SplitTableSpans:
    def process(self, document_text):
        text = document_text or ''
        lines = text.split('\n')
        offsets, offset = [], 0
        for line in lines:
            offsets.append(offset)
            offset += len(line) + 1
        index, cursor, span_index = 0, 0, 0
        while index < len(lines):
            if not table_start(lines, index):
                index += 1
                continue
            first = index
            last = first + 2
            while last < len(lines) and pipe_row(lines[last]):
                # 两张表之间的空行可能已被规范化删掉；新表头+分隔行仍可划清边界。
                if table_start(lines, last):
                    break
                last += 1
            caption_index = first - 1
            # 表名与表头之间可能有缩写说明，例如 'CI, confidence interval; ICC, ...'。
            # 只跨过这种说明行；不跨越一般正文去猜表名归属。
            while caption_index >= 0 and re.match(r'^[A-Z][A-Za-z0-9 /_-]{0,15},', lines[caption_index]):
                caption_index -= 1
            has_caption = (caption_index >= 0 and offsets[caption_index] >= cursor
                           and CAPTION.match(lines[caption_index]))
            start = offsets[caption_index if has_caption else first]
            end = offsets[last - 1] + len(lines[last - 1])
            if start > cursor and text[cursor:start].strip():
                yield (span_index, 'TEXT', cursor, start, text[cursor:start], None)
                span_index += 1
            caption = '\n'.join(lines[caption_index:first]) if has_caption else ''
            table = make_table(lines, offsets, first, last, caption)
            yield (span_index, 'TABLE', start, end, text[start:end], table)
            span_index += 1
            cursor, index = end, last
        if text[cursor:].strip():
            yield (span_index, 'TEXT', cursor, len(text), text[cursor:], None)
$$;
