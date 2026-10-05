-- 评测的基础表。评测题只和原始 PDF 关联,不绑定 chunk、解析结果或检索配置(.harness/rules/eval-rules.md)。
-- 由 deploy.sql 调用,可以重复执行:表已经存在就不动。
-- 以后加列:在 CREATE TABLE 后面写 ALTER TABLE ... ADD COLUMN IF NOT EXISTS。
--
-- 三张表的关系:
--   CORPUS_FILES  语料快照:某个快照名下每篇文档对应哪个文件(sha256)。固定语料版本。
--   PDF_PAGES     PDF 自带文字层,按 sha256 + 页码存,抽一次不再变;不随解析策略变化。
--                 只用来辅助出题和定位证据;最终依据是审核时在 PDF 上核对过的证据(文字层会抽错字符,比如 − 变成 /C0)。
--   QUESTIONS     题库:问题、参考答案、doc_id、sha256、页码、证据原文。

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

-- 按文件内容(sha256)存,同一个文件只抽一次。extractor 记下抽取工具和版本。
CREATE TABLE IF NOT EXISTS EVAL.PDF_PAGES (
  sha256       VARCHAR       NOT NULL,
  page_number  NUMBER        NOT NULL COMMENT 'Starting at 1, as shown in a PDF viewer',
  page_text    VARCHAR       COMMENT 'Text layer of the PDF page; NULL or empty for scanned pages',
  extractor    VARCHAR       NOT NULL COMMENT 'Tool and version, e.g. pypdf 6.8.0',
  extracted_at TIMESTAMP_LTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
  CONSTRAINT pk_pdf_pages PRIMARY KEY (sha256, page_number)
)
COMMENT = 'medrag v2 eval: PDF text layer per page, for drafting and locating evidence; the reviewed PDF evidence is the ground truth';

-- status:DRAFT 起草待审;APPROVED 审核通过(核对过 PDF);REJECTED 不用(包括已修订成新题的旧稿);
--   STALE 文件变了待复核;RETIRED 停用。只有 APPROVED 参与评测。
-- 题只增不改:要改一题就新建一题(revised_from 指向旧题),旧题设 REJECTED 或 RETIRED,历史结果仍可比。
-- source:AI_DRAFT 模型起草;REVIEW_REVISION 审核时按 PDF 改写。AI 起草的题审核通过后 source 仍是 AI_DRAFT,
--   不等于客户或专家从零标注的题。
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

-- 2026-10-04 审核后加的列。
ALTER TABLE EVAL.QUESTIONS ADD COLUMN IF NOT EXISTS evidence_parts ARRAY
  COMMENT 'All verbatim fragments that must be covered together, e.g. table header, row label and value; NULL means evidence_text only';
ALTER TABLE EVAL.QUESTIONS ADD COLUMN IF NOT EXISTS revised_from VARCHAR COMMENT 'question_id of the draft this one replaces';
ALTER TABLE EVAL.QUESTIONS ADD COLUMN IF NOT EXISTS draft_batch_id VARCHAR COMMENT 'One per DRAFT_QUESTIONS call or review import';
ALTER TABLE EVAL.QUESTIONS ADD COLUMN IF NOT EXISTS prompt_version VARCHAR COMMENT 'Version of the drafting prompt';
ALTER TABLE EVAL.QUESTIONS ADD COLUMN IF NOT EXISTS seed NUMBER COMMENT 'Sampling seed passed to DRAFT_QUESTIONS';
ALTER TABLE EVAL.QUESTIONS ADD COLUMN IF NOT EXISTS reviewed_by VARCHAR COMMENT 'Who reviewed against the PDF, and the review record';


-- select * from EVAL.QUESTIONS;
