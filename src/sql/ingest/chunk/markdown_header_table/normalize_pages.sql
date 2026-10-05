-- 规范化后再记页码偏移；后续切分、定位必须共用这一份文字。
USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

CREATE OR REPLACE FUNCTION CORE.NORMALIZE_MARKDOWN_PAGES(pages ARRAY)
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
