-- 只把紧邻表格、格式明确的脚注加入重复前缀；不跨普通段落猜测关联。
-- Notes / Abbreviations 或符号脚注可识别，字母脚注和跨页续表仍不保证关联。
USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

CREATE OR REPLACE FUNCTION CORE.ATTACH_TABLE_NOTES(table_data OBJECT, document_text VARCHAR, table_end INTEGER, enabled BOOLEAN)
RETURNS OBJECT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
HANDLER = 'attach'
AS
$$
import re
NOTE = re.compile(r'^(?:notes?\s*[:.]|abbreviations?\s*[:.]|(?:\*(?!\*)|[†‡])\s*\S)', re.I)


def attach(table_data, document_text, table_end, enabled):
    if not enabled:
        return table_data
    notes = []
    cursor = table_end
    while cursor < len(document_text) and document_text[cursor] == '\n':
        cursor += 1
    for line in document_text[table_end:].lstrip('\n').split('\n'):
        if not NOTE.match(line.strip()):
            break
        notes.append(line)
        cursor += len(line) + 1
    if notes:
        table_data = dict(table_data)
        table_data['prefix'] += '\n' + '\n'.join(notes)
        table_data['notes_end'] = min(cursor, len(document_text))
    return table_data
$$;
