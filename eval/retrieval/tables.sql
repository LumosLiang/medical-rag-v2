-- 保存实验参数、原始 top-k 和单块覆盖上限；检索结果与指标分离，便于重新评分。
USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

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
