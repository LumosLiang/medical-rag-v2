-- 审核导入:把对照 PDF 审核的结果写回 EVAL.QUESTIONS。
-- 用法:先往 EVAL.REVIEW_IMPORT 写一批审核结果(review_batch 相同),再
--   CALL MEDRAG.EVAL.APPLY_REVIEW('<review_batch>');返回各决定的处理行数。
--
-- decision 的含义(只处理 DRAFT 题,已审核过的题不再改):
--   APPROVED  原题设 APPROVED,记下审核人、时间和备注。
--   REJECTED  原题设 REJECTED,不补题。
--   REVISE    按 new_* 字段写一道新题(source REVIEW_REVISION,revised_from 指向原题,状态 DRAFT,
--             改完还要再复核一次);原题设 REJECTED,备注写明改成了哪一题。
--             替换被拒的题也走 REVISE:同一篇文档写一道新题。
--   new_* 字段为空时沿用原题的值。

USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

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

CREATE OR REPLACE PROCEDURE EVAL.APPLY_REVIEW(p_review_batch VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = 'medrag v2 eval: apply one batch of review decisions (approve, reject, revise into new drafts)'
EXECUTE AS OWNER
AS
$$
DECLARE
  v_bad      INTEGER;
  v_revised  INTEGER;
  v_approved INTEGER;
  v_rejected INTEGER;
  bad_rows EXCEPTION (-20211, 'APPLY_REVIEW: some rows have an unknown decision, or point to a question that is missing or not DRAFT');
BEGIN
  -- 先检查整批:决定要合法,原题要存在且仍是 DRAFT。有一行不对就整批不处理。
  SELECT COUNT(*) INTO :v_bad
    FROM EVAL.REVIEW_IMPORT r
    LEFT JOIN EVAL.QUESTIONS q ON q.question_id = r.question_id
   WHERE r.review_batch = :p_review_batch
     AND (r.decision NOT IN ('APPROVED', 'REJECTED', 'REVISE')
          OR q.question_id IS NULL
          OR q.status <> 'DRAFT');
  IF (v_bad > 0) THEN
    RAISE bad_rows;
  END IF;

  BEGIN TRANSACTION;

  -- 修订:写新题。新题 ID 由原题 ID 和新问题算出,重跑同一批不会写出不同的 ID。
  INSERT INTO EVAL.QUESTIONS (
    question_id, snapshot_name, doc_id, sha256, page_number, question, reference_answer,
    evidence_text, evidence_parts, question_type, tags, evidence_in_pdf, status, source,
    revised_from, draft_batch_id, reviewer_note, reviewed_by)
  SELECT 'q_' || LEFT(SHA2(q.question_id || '|' || COALESCE(r.new_question, q.question), 256), 16),
         q.snapshot_name, q.doc_id, q.sha256,
         COALESCE(r.new_page_number, q.page_number),
         COALESCE(r.new_question, q.question),
         COALESCE(r.new_reference_answer, q.reference_answer),
         COALESCE(r.new_evidence_text, q.evidence_text),
         COALESCE(r.new_evidence_parts, q.evidence_parts),
         COALESCE(r.new_question_type, q.question_type),
         COALESCE(r.new_tags, q.tags),
         EVAL.EVIDENCE_LOCATED(p.page_text, COALESCE(r.new_evidence_text, q.evidence_text),
                               COALESCE(r.new_evidence_parts, q.evidence_parts)),
         'DRAFT', 'REVIEW_REVISION', q.question_id, :p_review_batch, r.note, r.reviewed_by
    FROM EVAL.REVIEW_IMPORT r
    JOIN EVAL.QUESTIONS q ON q.question_id = r.question_id
    LEFT JOIN EVAL.PDF_PAGES p
      ON p.sha256 = q.sha256 AND p.page_number = COALESCE(r.new_page_number, q.page_number)
   WHERE r.review_batch = :p_review_batch
     AND r.decision = 'REVISE';
  v_revised := SQLROWCOUNT;

  -- 原题:通过的设 APPROVED;拒绝和已修订的设 REJECTED。备注追加,不覆盖草稿阶段的备注。
  UPDATE EVAL.QUESTIONS q
     SET status        = IFF(r.decision = 'APPROVED', 'APPROVED', 'REJECTED'),
         reviewed_at   = CURRENT_TIMESTAMP(),
         reviewed_by   = r.reviewed_by,
         reviewer_note = COALESCE(q.reviewer_note || '; ', '')
                         || r.decision
                         || IFF(r.decision = 'REVISE',
                                ' into q_' || LEFT(SHA2(q.question_id || '|'
                                                   || COALESCE(r.new_question, q.question), 256), 16),
                                '')
                         || COALESCE(': ' || r.note, '')
    FROM EVAL.REVIEW_IMPORT r
   WHERE r.review_batch = :p_review_batch
     AND q.question_id = r.question_id
     AND q.status = 'DRAFT';
  SELECT COUNT_IF(decision = 'APPROVED'), COUNT_IF(decision <> 'APPROVED')
    INTO :v_approved, :v_rejected
    FROM EVAL.REVIEW_IMPORT
   WHERE review_batch = :p_review_batch;

  COMMIT;
  RETURN v_approved::VARCHAR || ' approved, ' || v_rejected::VARCHAR || ' rejected or revised, '
      || v_revised::VARCHAR || ' new drafts';
EXCEPTION
  WHEN OTHER THEN
    ROLLBACK;
    RAISE;
END;
$$;

-- select r.decision, q.status, count(*) from EVAL.REVIEW_IMPORT r join EVAL.QUESTIONS q using (question_id) group by 1, 2;
