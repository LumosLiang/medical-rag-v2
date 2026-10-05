-- 输入的 token 数由 SQL 用 COUNT_TOKENS 算好；Python 只负责分组。
-- 先尽量保留完整行组，超过目标再拆成多块，每块重复表名、表头和组标签。
USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

CREATE OR REPLACE FUNCTION CORE.PACK_TABLE_ROWS(table_data OBJECT, target_tokens INTEGER)
RETURNS TABLE (piece_index INTEGER, chunk_text VARCHAR, source_start INTEGER, source_end INTEGER)
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
HANDLER = 'PackTableRows'
AS
$$
class PackTableRows:
    def process(self, table_data, target_tokens):
        prefix = table_data['prefix']
        prefix_tokens = table_data['prefix_tokens']
        rows = table_data['rows']
        if not rows:
            yield (0, prefix, table_data['header_start'],
                   table_data['header_end'])
            return
        groups = []
        for index, row in enumerate(rows):
            key = row.get('group')
            if not groups or groups[-1][0] != key:
                groups.append((key, []))
            groups[-1][1].append(row)
        pieces, pending, pending_tokens = [], [], prefix_tokens
        for group_index, group_rows in groups:
            group_tokens = sum(row['tokens'] for row in group_rows)
            if pending and pending_tokens + group_tokens > target_tokens:
                pieces.append(pending)
                pending, pending_tokens = [], prefix_tokens
            label = rows[group_index] if group_index is not None else None
            for row in group_rows:
                if pending and pending_tokens + row['tokens'] > target_tokens:
                    # 不留下一个只有组标签的块；单行无法放下时交给最终精确计数检查。
                    if not (label and len(pending) == 1 and pending[0] is label):
                        pieces.append(pending)
                        pending, pending_tokens = [], prefix_tokens
                        if label and row is not label:
                            pending.append(label)
                            pending_tokens += label['tokens']
                pending.append(row)
                pending_tokens += row['tokens']
        if pending:
            pieces.append(pending)
        for index, piece in enumerate(pieces):
            yield (index, prefix + '\n' + '\n'.join(row['text'] for row in piece),
                   min(row['start'] for row in piece), max(row['end'] for row in piece))
$$;
