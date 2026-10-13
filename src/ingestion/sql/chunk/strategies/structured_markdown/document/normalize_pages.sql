-- 输入：AI_PARSE_DOCUMENT 的 pages；输出：整篇 Markdown 和每页在全文中的 [start, end) 范围。
-- 去掉空行与行尾空白，减少原生标题切分对空白的改写；按页码拼接，保留跨页正文。
-- 这份规范化文字是切分和定位共同的坐标系，不是另一次 PDF 解析。

USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

CREATE OR REPLACE FUNCTION CORE.PREPARE_MARKDOWN_DOCUMENT(pages ARRAY)
RETURNS OBJECT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
HANDLER = 'normalize'
AS
$$
def normalize(pages):
    parts, ranges = [], []
    offset = 0
    for page in sorted(pages, key=lambda item: item['index']):
        lines = [line.rstrip() for line in (page.get('content') or '').replace('\r', '').split('\n')]
        text = '\n'.join(line for line in lines if line.strip())
        if not text:
            continue
        if parts:
            offset += 1  # 页间连接的一个换行也占一个字符。
        ranges.append({'page': page['index'], 'start': offset, 'end': offset + len(text)})
        parts.append(text)
        offset += len(text)
    # 全部偏移都是 Python 的 0 起始、右端不包含；页码也保持解析器的 0 起始。
    return {'text': '\n'.join(parts), 'pages': ranges}
$$;
