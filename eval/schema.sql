-- 评测存储结构：语料与问题、审核输入、固定题集、实验与结果。
-- 题集依据原始 PDF 建立；检索结果记录块，但不反向定义题目的正确证据。
USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

CREATE TABLE IF NOT EXISTS EVAL.CORPUS_FILES (
  snapshot_name VARCHAR       NOT NULL COMMENT 'Corpus version; questions are written against one snapshot',
  doc_id        VARCHAR       NOT NULL COMMENT 'File name without .pdf, i.e. the PMCID',
  relative_path VARCHAR       NOT NULL,
  sha256        VARCHAR       NOT NULL COMMENT 'SHA-256 of the PDF bytes; identifies the exact file',
  size          NUMBER,
  etag          VARCHAR       COMMENT 'Stage etag at snapshot time, for joining with CORE.CHUNKS',
  page_count    NUMBER        NOT NULL,
  captured_at   TIMESTAMP_LTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
  CONSTRAINT pk_corpus_files PRIMARY KEY (snapshot_name, doc_id)
)
COMMENT = 'medrag v2 eval: which file (by sha256) each doc_id was in a corpus snapshot';

CREATE TABLE IF NOT EXISTS EVAL.PDF_PAGES (
  sha256       VARCHAR       NOT NULL,
  page_number  NUMBER        NOT NULL COMMENT 'Starting at 1, as shown in a PDF viewer',
  page_text    VARCHAR       COMMENT 'Text layer of the PDF page; NULL or empty for scanned pages',
  extractor    VARCHAR       NOT NULL COMMENT 'Tool and version, e.g. pypdf 6.8.0',
  extracted_at TIMESTAMP_LTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
  CONSTRAINT pk_pdf_pages PRIMARY KEY (sha256, page_number)
)
COMMENT = 'medrag v2 eval: PDF text layer per page, for drafting and locating evidence; the reviewed PDF evidence is the ground truth';

CREATE TABLE IF NOT EXISTS EVAL.QUESTIONS (
  question_id      VARCHAR       NOT NULL,
  snapshot_name    VARCHAR       NOT NULL,
  doc_id           VARCHAR       NOT NULL,
  sha256           VARCHAR       NOT NULL COMMENT 'File the question was written against',
  page_number      NUMBER        NOT NULL COMMENT 'PDF page of the evidence, starting at 1',
  question         VARCHAR       NOT NULL,
  reference_answer VARCHAR       NOT NULL COMMENT 'Short factual answer; judged on key facts, not wording',
  evidence_text    VARCHAR       NOT NULL COMMENT 'Main verbatim passage as seen in the PDF; for tables, see evidence_parts',
  question_type    VARCHAR       COMMENT 'e.g. fact, number, conclusion, method',
  tags             ARRAY         COMMENT 'e.g. table, section-specific, paraphrased, abbreviation',
  evidence_in_pdf  BOOLEAN       COMMENT 'Evidence located in the PDF_PAGES text layer of that page (NORMALIZE_TEXT); a locating aid, not proof the answer is right',
  status           VARCHAR       NOT NULL DEFAULT 'DRAFT',
  source           VARCHAR       NOT NULL COMMENT 'AI_DRAFT or HUMAN',
  draft_model      VARCHAR       COMMENT 'Model used for AI_DRAFT',
  reviewer_note    VARCHAR,
  created_at       TIMESTAMP_LTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
  reviewed_at      TIMESTAMP_LTZ,
  CONSTRAINT pk_questions PRIMARY KEY (question_id)
)
COMMENT = 'medrag v2 eval: questions tied to the original PDF (doc, sha256, page, evidence), not to chunks or configs';

ALTER TABLE EVAL.QUESTIONS ADD COLUMN IF NOT EXISTS evidence_parts ARRAY
  COMMENT 'All verbatim fragments that must be covered together, e.g. table header, row label and value; NULL means evidence_text only';

ALTER TABLE EVAL.QUESTIONS ADD COLUMN IF NOT EXISTS revised_from VARCHAR COMMENT 'question_id of the draft this one replaces';

ALTER TABLE EVAL.QUESTIONS ADD COLUMN IF NOT EXISTS draft_batch_id VARCHAR COMMENT 'One per DRAFT_QUESTIONS call or review import';

ALTER TABLE EVAL.QUESTIONS ADD COLUMN IF NOT EXISTS prompt_version VARCHAR COMMENT 'Version of the drafting prompt';

ALTER TABLE EVAL.QUESTIONS ADD COLUMN IF NOT EXISTS seed NUMBER COMMENT 'Sampling seed passed to DRAFT_QUESTIONS';

ALTER TABLE EVAL.QUESTIONS ADD COLUMN IF NOT EXISTS reviewed_by VARCHAR COMMENT 'Who reviewed against the PDF, and the review record';

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

CREATE TABLE IF NOT EXISTS EVAL.REVIEW_IMPORT (
  review_batch         VARCHAR       NOT NULL,
  question_id          VARCHAR       NOT NULL COMMENT 'Draft being reviewed',
  decision             VARCHAR       NOT NULL COMMENT 'APPROVED, REJECTED or REVISE',
  note                 VARCHAR,
  reviewed_by          VARCHAR       NOT NULL COMMENT 'Reviewer and review record',
  new_question         VARCHAR,
  new_reference_answer VARCHAR,
  new_page_number      NUMBER,
  new_evidence_text    VARCHAR       COMMENT 'As seen in the PDF; may differ from the text layer',
  new_evidence_parts   ARRAY,
  new_question_type    VARCHAR,
  new_tags             ARRAY,
  loaded_at            TIMESTAMP_LTZ NOT NULL DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'medrag v2 eval: review decisions waiting to be applied to QUESTIONS by APPLY_REVIEW';

CREATE TABLE IF NOT EXISTS EVAL.QUESTION_SETS (
  set_name    VARCHAR       NOT NULL,
  question_id VARCHAR       NOT NULL,
  frozen_at   TIMESTAMP_LTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
  CONSTRAINT pk_question_sets PRIMARY KEY (set_name, question_id)
)
COMMENT = 'medrag v2 eval: frozen question sets; experiments are compared only within one set';
