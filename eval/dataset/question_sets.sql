-- 冻结已审核问题的 ID，供多个实验共享同一套题；不绑定解析或切分配置。
USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

CREATE TABLE IF NOT EXISTS EVAL.QUESTION_SETS (
  set_name    VARCHAR       NOT NULL,
  question_id VARCHAR       NOT NULL,
  frozen_at   TIMESTAMP_LTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
  CONSTRAINT pk_question_sets PRIMARY KEY (set_name, question_id)
)
COMMENT = 'medrag v2 eval: frozen question sets; experiments are compared only within one set';

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
