-- 在固定题集上调用一个搜索服务，保存原始结果与查询权重，最后统一评分；不负责出题。
USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

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
  v_questions INTEGER;
  v_n         INTEGER DEFAULT 0;
  v_qid       VARCHAR;
  v_request   VARCHAR;
  v_sql       VARCHAR;
  v_started   TIMESTAMP_LTZ;
  v_latency   NUMBER;
  experiment_exists EXCEPTION (-20231, 'RUN_RETRIEVAL_EVAL: this experiment_id already exists; use a new id');
  invalid_input EXCEPTION (-20232, 'RUN_RETRIEVAL_EVAL: question set must not be empty and top_k must be a positive integer');
BEGIN
  SELECT COUNT(*) INTO :v_existing
    FROM EVAL.EXPERIMENTS
   WHERE experiment_id = :p_experiment_id;
  IF (v_existing > 0) THEN
    RAISE experiment_exists;
  END IF;

  -- 在写实验记录和调用搜索前验证输入；空题集不能成为“已完成”的实验。
  SELECT COUNT(*) INTO :v_questions
    FROM EVAL.QUESTION_SETS
   WHERE set_name = :p_set_name;
  IF (v_questions = 0 OR p_top_k IS NULL OR p_top_k <= 0 OR p_top_k <> FLOOR(p_top_k)) THEN
    RAISE invalid_input;
  END IF;

  INSERT INTO EVAL.EXPERIMENTS (
    experiment_id, set_name, search_service, config_name, top_k, scoring_rule, params, note
  )
  SELECT :p_experiment_id, :p_set_name, :p_search_service, :p_config_name, :p_top_k,
         'evidence_covered_v2', OBJECT_CONSTRUCT('scoring_config', COALESCE(:p_scoring_config, OBJECT_CONSTRUCT())), :p_note;

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
