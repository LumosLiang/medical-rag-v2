-- 输入：表格 prefix、数据行及 SQL 计算的逐行 token；输出：可检索表格块及原文行范围。
-- 优先把同一组放在一起；放不下再逐行拆，每块重复表名、表头和所属组标签。
-- 逐行 token 相加只是预算估计，SQL 随后对完整块精确复核；单行或表头过大交给补切兜底。

USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

CREATE OR REPLACE FUNCTION CORE.BUILD_TABLE_CHUNKS(table_data OBJECT, target_tokens INTEGER)
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
        # group 是组标签在 rows 中的下标；None 表示尚未出现标签。
        groups = []
        for row in rows:
            key = row.get('group')
            if not groups or groups[-1][0] != key:
                groups.append((key, []))
            groups[-1][1].append(row)
        # pending 是正在构建的块，token 预算每次都包含重复的 prefix。
        pieces, pending, pending_tokens = [], [], prefix_tokens
        for label_index, group_rows in groups:
            # 整组可以放下就不拆；放不下先结束上一块，再在本组内部按行拆。
            group_tokens = sum(row['tokens'] for row in group_rows)
            if pending and pending_tokens + group_tokens > target_tokens:
                pieces.append(pending)
                pending, pending_tokens = [], prefix_tokens
            label = rows[label_index] if label_index is not None else None
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
        # 来源范围包含重复的组标签；因此引用有时会覆盖标签所在的更早页面。
        for index, piece in enumerate(pieces):
            yield (index, prefix + '\n' + '\n'.join(row['text'] for row in piece),
                   min(row['start'] for row in piece), max(row['end'] for row in piece))
$$;
