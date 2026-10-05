-- 检索评测:在固定的题集上跑某个检索服务,记下每题的 top-k 结果,判断每个块是否覆盖这题的原始证据。
-- 由 deploy.sql 调用,可以重复执行:表已经存在就不动;函数、过程、视图用 CREATE OR REPLACE 更新。
-- 用法:
--   1. 固定题集(一次):CALL MEDRAG.EVAL.FREEZE_QUESTION_SET('<set_name>', '<snapshot_name>');
--   2. 跑一次实验:CALL MEDRAG.EVAL.RUN_RETRIEVAL_EVAL('<experiment_id>', '<set_name>', '<search_service>', '<config_name>', <top_k>, '<note>');
--      要调检索权重时加第 7 个参数 scoring_config(OBJECT),原样放进 SEARCH_PREVIEW 请求,也记进 EXPERIMENTS.params;
--      六参数入口等于传空 OBJECT,即 Cortex 默认权重。
--      只改了评分规则时不用重新检索:CALL MEDRAG.EVAL.RESCORE_EXPERIMENT('<experiment_id>');
--   3. 看结果:SELECT * FROM MEDRAG.EVAL.RETRIEVAL_METRICS WHERE experiment_id = '<experiment_id>';
--
-- 评分规则 v2(EVAL.EVIDENCE_COVERED,改它要记进 eval-rules.md,并用 RESCORE_EXPERIMENT 对历史实验重算):
--   - 证据 = evidence_parts 的每个片段;没有片段时用 evidence_text。
--   - 一个片段被一个块覆盖:片段的词(小写字母串和数字)至少 90% 在块里出现,而且片段里的数字全部出现。
--     数字保留小数点和负号:−6.1 和 6.1、1.2 和 12 不算同一个数。
--   - 一个块覆盖这题:所有片段都被这一个块覆盖。
--   - v2(2026-10-04)只改格式处理,不改判定:字母间的连字符(含两边空格)一律去掉;紧跟在 - 后面的 - 不算负号;
--     数字的千分位分隔(逗号或空格)去掉。v1 把 dem - onstrated、(1--5)、173 315 误判为未覆盖。
-- 和 NORMALIZE_TEXT(只用来在文字层里定位)是两套规则。
--
-- 每题还算一个上限 coverable:这个切分配置下,这篇文档的块里有没有任何一个覆盖证据。
--   coverable = FALSE:解析或切分把证据丢了/切散了,检索再好也找不到。
--   coverable = TRUE 但 top-k 没命中:检索没找到。

USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

-- 题集固定后不再变:要加题、换题就建一个新的题集名。实验只在同一个题集上比较。
CREATE TABLE IF NOT EXISTS EVAL.QUESTION_SETS (
  set_name    VARCHAR       NOT NULL,
  question_id VARCHAR       NOT NULL,
  frozen_at   TIMESTAMP_LTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
  CONSTRAINT pk_question_sets PRIMARY KEY (set_name, question_id)
)
COMMENT = 'medrag v2 eval: frozen question sets; experiments are compared only within one set';

CREATE TABLE IF NOT EXISTS EVAL.EXPERIMENTS (
  experiment_id  VARCHAR       NOT NULL,
  set_name       VARCHAR       NOT NULL,
  search_service VARCHAR       NOT NULL COMMENT 'Fully qualified Cortex Search service',
  config_name    VARCHAR       NOT NULL COMMENT 'Chunk config indexed by the service; used for the coverable ceiling',
  top_k          NUMBER        NOT NULL,
  scoring_rule   VARCHAR       NOT NULL COMMENT 'Version of EVIDENCE_COVERED used',
  params         OBJECT        COMMENT 'Other settings of this run; new factors go here, not into new columns',
  note           VARCHAR,
  started_at     TIMESTAMP_LTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
  finished_at    TIMESTAMP_LTZ,
  CONSTRAINT pk_experiments PRIMARY KEY (experiment_id)
)
COMMENT = 'medrag v2 eval: one row per retrieval evaluation run';

-- 每题每个 rank 一行,只存原始结果和逐块判定;指标在视图里算。
CREATE TABLE IF NOT EXISTS EVAL.RETRIEVAL_RESULTS (
  experiment_id VARCHAR NOT NULL,
  question_id   VARCHAR NOT NULL,
  rank          NUMBER  NOT NULL COMMENT 'Starting at 1',
  chunk_id      VARCHAR,
  doc_id        VARCHAR,
  page_start    NUMBER  COMMENT 'From the chunk; parser pages start at 0',
  chunk_text    VARCHAR,
  hit_doc       BOOLEAN COMMENT 'Chunk is from the question document',
  hit_evidence  BOOLEAN COMMENT 'Chunk covers the evidence (scoring rule of the experiment)',
  latency_ms    NUMBER  COMMENT 'Search call time for this question, repeated on each rank',
  CONSTRAINT pk_retrieval_results PRIMARY KEY (experiment_id, question_id, rank)
)
COMMENT = 'medrag v2 eval: raw top-k results per question with per-chunk judgements';

CREATE TABLE IF NOT EXISTS EVAL.COVERAGE_CEILING (
  experiment_id VARCHAR NOT NULL,
  question_id   VARCHAR NOT NULL,
  coverable     BOOLEAN NOT NULL COMMENT 'Some chunk of the document (this config) covers the evidence',
  n_doc_chunks  NUMBER,
  CONSTRAINT pk_coverage_ceiling PRIMARY KEY (experiment_id, question_id)
)
COMMENT = 'medrag v2 eval: whether parse + chunk kept the evidence in at least one chunk';

-- 评分规则 v2。见文件头。
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

CREATE OR REPLACE PROCEDURE EVAL.FREEZE_QUESTION_SET(p_set_name VARCHAR, p_snapshot_name VARCHAR)
RETURNS NUMBER
LANGUAGE SQL
COMMENT = 'medrag v2 eval: freeze all APPROVED questions of a snapshot into a new question set'
EXECUTE AS OWNER
AS
$$
DECLARE
  v_existing INTEGER;
  set_exists EXCEPTION (-20221, 'FREEZE_QUESTION_SET: this set name already exists; use a new name');
BEGIN
  SELECT COUNT(*) INTO :v_existing
    FROM EVAL.QUESTION_SETS
   WHERE set_name = :p_set_name;
  IF (v_existing > 0) THEN
    RAISE set_exists;
  END IF;
  INSERT INTO EVAL.QUESTION_SETS (set_name, question_id)
    SELECT :p_set_name, question_id
      FROM EVAL.QUESTIONS
     WHERE snapshot_name = :p_snapshot_name
       AND status = 'APPROVED';
  RETURN SQLROWCOUNT;
END;
$$;

-- 评分:按当前评分规则重判一个实验的所有块,并重算上限。检索结果不动,所以改了规则可以对历史实验重跑。
-- 上限按实验登记的切分配置,在快照时的文件版本(etag)的块里算。
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

CREATE OR REPLACE PROCEDURE EVAL.RUN_RETRIEVAL_EVAL(
  p_experiment_id  VARCHAR,
  p_set_name       VARCHAR,
  p_search_service VARCHAR,
  p_config_name    VARCHAR,
  p_top_k          NUMBER,
  p_note           VARCHAR,
  p_scoring_config OBJECT
)
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = 'medrag v2 eval: run every question of a set against one search service and judge evidence coverage'
EXECUTE AS OWNER
AS
$$
DECLARE
  v_existing  INTEGER;
  v_n         INTEGER DEFAULT 0;
  v_qid       VARCHAR;
  v_request   VARCHAR;
  v_sql       VARCHAR;
  v_started   TIMESTAMP_LTZ;
  v_latency   NUMBER;
  experiment_exists EXCEPTION (-20231, 'RUN_RETRIEVAL_EVAL: this experiment_id already exists; use a new id');
BEGIN
  SELECT COUNT(*) INTO :v_existing
    FROM EVAL.EXPERIMENTS
   WHERE experiment_id = :p_experiment_id;
  IF (v_existing > 0) THEN
    RAISE experiment_exists;
  END IF;

  INSERT INTO EVAL.EXPERIMENTS (
    experiment_id, set_name, search_service, config_name, top_k, scoring_rule, params, note
  )
  SELECT :p_experiment_id, :p_set_name, :p_search_service, :p_config_name, :p_top_k,
         'evidence_covered_v2', OBJECT_CONSTRUCT('scoring_config', :p_scoring_config), :p_note;

  -- 1. 逐题检索。SEARCH_PREVIEW 的参数必须是常量,所以每题拼一条语句执行;
  --    请求 JSON 放进 SQL 字符串前,先把反斜杠(JSON 里转义双引号用的)变成两个,再把单引号变成两个。
  -- 游标的查询要用参数,所以先放进 RESULTSET 再遍历。
  LET rs RESULTSET := (
    SELECT q.question_id, q.question
      FROM EVAL.QUESTION_SETS s
      JOIN EVAL.QUESTIONS q ON q.question_id = s.question_id
     WHERE s.set_name = :p_set_name
     ORDER BY q.question_id
  );
  LET c_questions CURSOR FOR rs;
  FOR r IN c_questions DO
    v_qid := r.question_id;
    v_request := TO_JSON(OBJECT_CONSTRUCT(
                   'query', r.question,
                   'columns', ARRAY_CONSTRUCT('chunk_id', 'doc_id', 'page_start', 'chunk_text'),
                   'limit', p_top_k,
                   'scoring_config', COALESCE(p_scoring_config, OBJECT_CONSTRUCT())));
    v_sql := 'INSERT INTO EVAL.RETRIEVAL_RESULTS (experiment_id, question_id, rank, chunk_id, doc_id, page_start, chunk_text) '
          || 'SELECT ''' || REPLACE(p_experiment_id, '''', '''''') || ''', ''' || v_qid || ''', f.index + 1, '
          || 'f.value:chunk_id::VARCHAR, f.value:doc_id::VARCHAR, f.value:page_start::NUMBER, f.value:chunk_text::VARCHAR '
          || 'FROM LATERAL FLATTEN(PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW('''
          || REPLACE(p_search_service, '''', '''''') || ''', '''
          || REPLACE(REPLACE(v_request, '\\', '\\\\'), '''', '''''') || ''')):results) f';
    v_started := CURRENT_TIMESTAMP();
    EXECUTE IMMEDIATE :v_sql;
    v_latency := TIMESTAMPDIFF(millisecond, v_started, CURRENT_TIMESTAMP());
    UPDATE EVAL.RETRIEVAL_RESULTS
       SET latency_ms = :v_latency
     WHERE experiment_id = :p_experiment_id
       AND question_id = :v_qid;
    v_n := v_n + 1;
  END FOR;

  -- 2. 评分:逐块判定和上限,和重算共用一个过程。
  CALL EVAL.RESCORE_EXPERIMENT(:p_experiment_id);

  UPDATE EVAL.EXPERIMENTS
     SET finished_at = CURRENT_TIMESTAMP()
   WHERE experiment_id = :p_experiment_id;
  RETURN v_n::VARCHAR || ' questions';
END;
$$;

-- 六参数入口:不传权重,用 Cortex 默认;转调上面的七参数过程,只维护一份检索循环。
CREATE OR REPLACE PROCEDURE EVAL.RUN_RETRIEVAL_EVAL(
  p_experiment_id  VARCHAR,
  p_set_name       VARCHAR,
  p_search_service VARCHAR,
  p_config_name    VARCHAR,
  p_top_k          NUMBER,
  p_note           VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
  v_result VARCHAR;
BEGIN
  CALL EVAL.RUN_RETRIEVAL_EVAL(:p_experiment_id, :p_set_name, :p_search_service,
    :p_config_name, :p_top_k, :p_note, OBJECT_CONSTRUCT()) INTO :v_result;
  RETURN v_result;
END;
$$;

-- 每个实验一行总体,再按题型各一行。rank 从 1 开始,MRR 按第一个命中的 rank 算,没命中记 0。
CREATE OR REPLACE VIEW EVAL.RETRIEVAL_METRICS
COMMENT = 'medrag v2 eval: per experiment (and per question type) doc/evidence hit@k, MRR, ceiling and latency'
AS
WITH per_question AS (
  SELECT rr.experiment_id, rr.question_id, q.question_type,
         MIN(IFF(rr.hit_doc, rr.rank, NULL))      AS first_doc_rank,
         MIN(IFF(rr.hit_evidence, rr.rank, NULL)) AS first_evidence_rank,
         MAX(rr.latency_ms)                       AS latency_ms
    FROM EVAL.RETRIEVAL_RESULTS rr
    JOIN EVAL.QUESTIONS q ON q.question_id = rr.question_id
   GROUP BY rr.experiment_id, rr.question_id, q.question_type
),
scored AS (
  SELECT p.*, c.coverable
    FROM per_question p
    LEFT JOIN EVAL.COVERAGE_CEILING c
      ON c.experiment_id = p.experiment_id
     AND c.question_id = p.question_id
)
SELECT experiment_id,
       COALESCE(question_type, 'ALL')                                  AS question_type,
       COUNT(*)                                                        AS n_questions,
       ROUND(AVG(IFF(first_doc_rank <= 1, 1, 0)), 3)                   AS doc_hit_at_1,
       ROUND(AVG(IFF(first_doc_rank <= 5, 1, 0)), 3)                   AS doc_hit_at_5,
       ROUND(AVG(IFF(first_doc_rank IS NOT NULL, 1, 0)), 3)            AS doc_hit_at_k,
       ROUND(AVG(COALESCE(1 / first_doc_rank, 0)), 3)                  AS doc_mrr,
       ROUND(AVG(IFF(first_evidence_rank <= 1, 1, 0)), 3)              AS evidence_hit_at_1,
       ROUND(AVG(IFF(first_evidence_rank <= 5, 1, 0)), 3)              AS evidence_hit_at_5,
       ROUND(AVG(IFF(first_evidence_rank IS NOT NULL, 1, 0)), 3)       AS evidence_hit_at_k,
       ROUND(AVG(COALESCE(1 / first_evidence_rank, 0)), 3)             AS evidence_mrr,
       ROUND(AVG(IFF(coverable, 1, 0)), 3)                             AS coverable_rate,
       ROUND(MEDIAN(latency_ms))                                       AS latency_p50_ms
  FROM scored
 GROUP BY GROUPING SETS ((experiment_id), (experiment_id, question_type));

-- call EVAL.FREEZE_QUESTION_SET('qset_v1', 'corpus_2026_10_03');
-- call EVAL.RUN_RETRIEVAL_EVAL('baseline_once_1200_200_k10', 'qset_v1', 'MEDRAG.CORE.MEDICAL_CHUNKS_RECURSIVE_ONCE_1200_200', 'recursive_once_1200_200', 10, 'baseline');
-- select * from EVAL.RETRIEVAL_METRICS order by experiment_id, question_type;
