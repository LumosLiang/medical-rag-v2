-- 输入：规范化全文；输出：按原文顺序排列的 TEXT / TABLE 段及字符位置。
-- 表格用“管道表头 + Markdown 分隔行”识别，先从正文拆出，避免通用 splitter 把表头和数据分开。
-- table_data.prefix 保存表名与表头；rows 保存数据行、组标签和各行原文位置。此步不计算 token。

USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

CREATE OR REPLACE FUNCTION CORE.EXTRACT_MARKDOWN_ELEMENTS(document_text VARCHAR)
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
    body = line.strip()
    if body.startswith('|'):
        body = body[1:]
    if body.endswith('|') and not body.endswith('\\|'):
        body = body[:-1]
    return [cell.strip() for cell in re.split(r'(?<!\\)\|', body)]


def pipe_row(line):
    return line.lstrip().startswith('|') and len(cells(line)) > 1


def separator(line):
    return pipe_row(line) and all(SEPARATOR_CELL.fullmatch(cell) for cell in cells(line))


def table_start(lines, index):
    return index + 1 < len(lines) and pipe_row(lines[index]) and separator(lines[index + 1])


def make_table(lines, offsets, first, last, caption):
    # first 是表头，first+1 是 | --- | 分隔行；数据从其后开始。
    header_end = first + 2
    # 医学表格常有多层表头：分隔行后，首列空白的行仍是表头。
    # 首列空白只是多层表头的启发式；若数据行也首列空白，会误归入 prefix（见 README）。
    while header_end < last and not cells(lines[header_end])[0]:
        header_end += 1
    # prefix 会在每个表格块重复；单元格原文保留，不推断合并单元格。
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
        # cursor 是已输出段的结束位置；TEXT 和 TABLE 一起覆盖全文，不吞掉普通正文。
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
            # 只关联紧邻当前表格的前置表名，不能拿正文中提到的 Table N 猜关联。
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
