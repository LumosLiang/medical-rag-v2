-- 评分 v2：每个片段的词至少 90% 出现，数值全部出现，所有片段必须在同一个块内。
-- RESCORE 复用该规则重判原始结果与覆盖上限，不重新检索；词袋不判断组别对应或比较符号。
USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

CREATE OR REPLACE FUNCTION EVAL.EVIDENCE_COVERED(
  chunk_text     VARCHAR,
  evidence_text  VARCHAR,
  evidence_parts ARRAY
)
RETURNS BOOLEAN
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
HANDLER = 'covered'
COMMENT = 'medrag v2 eval: scoring rule v2, whether one chunk covers all evidence fragments'
AS
$$
import re
import unicodedata
from collections import Counter

# 数字前的 - 只在前面不是字母数字、小数点或另一个 - 时算负号,所以 1.2–1.7、(1--5) 里都是正数。
TOKEN = re.compile(r"(?:(?<![\w.\-])-)?\d+(?:\.\d+)?|[a-z]+")
NUMBER = re.compile(r"^-?\d")

def tokens(text):
    t = unicodedata.normalize("NFKC", text or "").lower()
    t = t.replace("\u2212", "-")                         # 数学减号 → -
    t = re.sub(r"(?<=[a-z])\s*-\s*(?=[a-z])", "", t)    # 字母间连字符:associ- ations、all-cause 两边一致去掉
    # 千分位 63,998、173 315 → 63998、173315;只合并"1–3 位整数 + 正好 3 位",不碰小数和表格里相邻的数
    t = re.sub(r"(?<![\d.])(\d{1,3})[, ](\d{3})(?![\d.,])", r"\1\2", t)
    return TOKEN.findall(t)

def part_covered(chunk_counts, part):
    toks = tokens(part)
    if not toks:
        return False
    need = Counter(toks)
    found = sum(min(n, chunk_counts[w]) for w, n in need.items())
    numbers_ok = all(chunk_counts[w] > 0 for w in need if NUMBER.match(w))
    return numbers_ok and found / len(toks) >= 0.9

def covered(chunk_text, evidence_text, evidence_parts):
    if not chunk_text:
        return False
    parts = [p for p in (evidence_parts or []) if p] or [evidence_text]
    chunk_counts = Counter(tokens(chunk_text))
    return all(part_covered(chunk_counts, p) for p in parts)
$$;

CREATE OR REPLACE PROCEDURE EVAL.RESCORE_EXPERIMENT(p_experiment_id VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = 'medrag v2 eval: (re)judge evidence coverage and the coverable ceiling of one experiment with the current scoring rule'
EXECUTE AS OWNER
AS
$$
DECLARE
  v_set_name    VARCHAR;
  v_config_name VARCHAR;
  v_rule        VARCHAR DEFAULT 'evidence_covered_v2';
BEGIN
  SELECT set_name, config_name
    INTO :v_set_name, :v_config_name
    FROM EVAL.EXPERIMENTS
   WHERE experiment_id = :p_experiment_id;

  BEGIN TRANSACTION;
  -- 逐块判定:是不是这题的文档、有没有覆盖证据。
  UPDATE EVAL.RETRIEVAL_RESULTS rr
     SET hit_doc      = (rr.doc_id = q.doc_id),
         hit_evidence = (rr.doc_id = q.doc_id)
                        AND EVAL.EVIDENCE_COVERED(rr.chunk_text, q.evidence_text, q.evidence_parts)
    FROM EVAL.QUESTIONS q
   WHERE rr.experiment_id = :p_experiment_id
     AND q.question_id = rr.question_id;

  -- 上限是从块表算出来的派生结果,重算时整份换掉。
  DELETE FROM EVAL.COVERAGE_CEILING
   WHERE experiment_id = :p_experiment_id;
  INSERT INTO EVAL.COVERAGE_CEILING (experiment_id, question_id, coverable, n_doc_chunks)
    SELECT :p_experiment_id, q.question_id,
           COALESCE(BOOLOR_AGG(
             EVAL.EVIDENCE_COVERED(c.chunk_text, q.evidence_text, q.evidence_parts)
           ), FALSE),
           COUNT(c.chunk_id)
      FROM EVAL.QUESTION_SETS s
      JOIN EVAL.QUESTIONS q ON q.question_id = s.question_id
      JOIN EVAL.CORPUS_FILES f ON f.snapshot_name = q.snapshot_name AND f.doc_id = q.doc_id
      LEFT JOIN CORE.CHUNKS c
        ON c.relative_path = f.relative_path
       AND c.etag = f.etag
       AND c.config_name = :v_config_name
     WHERE s.set_name = :v_set_name
     GROUP BY q.question_id;

  UPDATE EVAL.EXPERIMENTS
     SET scoring_rule = :v_rule
   WHERE experiment_id = :p_experiment_id;
  COMMIT;
  RETURN 'rescored with ' || v_rule;
EXCEPTION
  WHEN OTHER THEN
    ROLLBACK;
    RAISE;
END;
$$;
