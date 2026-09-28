-- 入库过程。由 deploy.sql 调用,可以重复执行(过程用 CREATE OR REPLACE 更新;改签名要先 DROP,见 docs/pitfalls.md)。
--
-- 三个过程:
--   INGEST.RUN_INGEST()                       task 调用的入口。消费 stream(环节 2A),再调用下面两个和 CORE.CHUNK_DOC。
--   INGEST.PLAN_BATCH(batch_id)               判断新增、覆盖、删除(环节 2B)。单独成一个过程,可以不连 stream、用假数据测。
--   INGEST.PARSE_FILE(path, etag, config)     解析一个文件版本(环节 3A)。
--
-- FILE_STATE.status 的约定(RUN_INGEST 依赖它):
--   PENDING  刚从 stream 写进来。PLAN_BATCH 结束时,这一批不能再有 PENDING 行。
--   READY    要解析、切分。PLAN_BATCH 设;RUN_INGEST 只处理 READY 的行,处理完设为 DONE 或 FAILED。
--   DONE     处理完。
--   FAILED   出错,error_message 是错误原文,retry_count 加一。要不要重试、什么时候重试,由 PLAN_BATCH 决定。
--   其它取值(比如 SKIPPED)由 PLAN_BATCH 自己定,RUN_INGEST 不碰。

USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

CREATE OR REPLACE PROCEDURE INGEST.RUN_INGEST()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
COMMENT = 'medrag v2: ingest entry called by the task; consume the stream, plan the batch, parse and chunk READY files'
AS
$$
DECLARE
  v_batch_id    VARCHAR DEFAULT UUID_STRING();
  v_config_name VARCHAR;
  v_captured    INTEGER DEFAULT 0;
  v_done        INTEGER DEFAULT 0;
  v_failed      INTEGER DEFAULT 0;
  v_row_batch   VARCHAR;
  v_path        VARCHAR;
  v_etag        VARCHAR;
  v_error       VARCHAR;
  no_active_config EXCEPTION (-20121, 'RUN_INGEST: no config with is_active = TRUE in CORE.PIPELINE_CONFIG');
  not_implemented  EXCEPTION (-20129, 'NOT_IMPLEMENTED: 环节 2A 消费 stream(sql/30_ingest.sql RUN_INGEST)');
  -- 游标在 FOR 开始时才执行,所以能看到 PLAN_BATCH 刚设的 READY。
  c_ready CURSOR FOR
    SELECT batch_id, relative_path, etag
      FROM INGEST.FILE_STATE
     WHERE status = 'READY'
     ORDER BY captured_at, relative_path;
BEGIN
  SELECT MAX(config_name) INTO :v_config_name
    FROM CORE.PIPELINE_CONFIG
   WHERE is_active;
  IF (v_config_name IS NULL) THEN
    RAISE no_active_config;
  END IF;

  -- ===== 你来写:环节 2A 消费 stream =====
  -- 要做什么:一条 INSERT ... SELECT,把 INGEST.CORPUS_STREAM 这一批写进 INGEST.FILE_STATE,batch_id 填 :v_batch_id。
  -- 输入:stream 的列(RELATIVE_PATH、SIZE、LAST_MODIFIED、ETAG ...)和元数据列(METADATA$ACTION、METADATA$ISUPDATE)。
  -- 输出:FILE_STATE 的列见 sql/11_tables.sql;status 不用填,默认是 PENDING。
  -- 注意:stream 只有被 DML 消费才前进,只 SELECT 不算(docs/pitfalls.md);一个 stream 只给这一个 task 消费。
  --       CORPUS_STREAM 要等 04_stage 部署后才有;在那之前可以拿环节 1 的 SPIKE_STREAM 练同一条语句。
  -- 要想清楚:这条语句提交之后 stream 就前进了,后面的步骤出错时,变更已经在 FILE_STATE 里,不会丢。
  --           要不要和 PLAN_BATCH 放进同一个事务,是这个环节的讨论项。
  -- 验收:docs/hands-on.md 环节 2A。
  -- 写完删掉下面这一行。
  RAISE not_implemented;
  -- ===== 到这里 =====

  SELECT COUNT(*) INTO :v_captured
    FROM INGEST.FILE_STATE
   WHERE batch_id = :v_batch_id;

  CALL INGEST.PLAN_BATCH(:v_batch_id);

  -- 一个文件失败不影响其它文件:记下错误,接着处理下一个。
  FOR r IN c_ready DO
    v_row_batch := r.batch_id;
    v_path      := r.relative_path;
    v_etag      := r.etag;
    BEGIN
      CALL INGEST.PARSE_FILE(:v_path, :v_etag, :v_config_name);
      CALL CORE.CHUNK_DOC(:v_path, :v_etag, :v_config_name, 'MEDRAG.CORE.CHUNKS');
      UPDATE INGEST.FILE_STATE
         SET status = 'DONE', error_message = NULL, updated_at = CURRENT_TIMESTAMP()
       WHERE batch_id = :v_row_batch AND relative_path = :v_path AND etag = :v_etag AND status = 'READY';
      v_done := v_done + 1;
    EXCEPTION
      WHEN OTHER THEN
        v_error := SQLERRM;
        UPDATE INGEST.FILE_STATE
           SET status = 'FAILED', error_message = :v_error, retry_count = retry_count + 1,
               updated_at = CURRENT_TIMESTAMP()
         WHERE batch_id = :v_row_batch AND relative_path = :v_path AND etag = :v_etag AND status = 'READY';
        v_failed := v_failed + 1;
    END;
  END FOR;

  -- 环节 8 之后在这里调用数据检查。

  RETURN 'batch ' || v_batch_id || ': captured ' || v_captured::VARCHAR
      || ', done ' || v_done::VARCHAR || ', failed ' || v_failed::VARCHAR;
END;
$$;

CREATE OR REPLACE PROCEDURE INGEST.PLAN_BATCH(p_batch_id VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
COMMENT = 'medrag v2: decide per file change whether it is new, overwritten or deleted; remove superseded chunks; mark rows READY'
AS
$$
DECLARE
  v_pending_left  INTEGER;
  pending_left    EXCEPTION (-20131, 'PLAN_BATCH: rows of this batch are still PENDING; every row must get a new status');
  not_implemented EXCEPTION (-20139, 'NOT_IMPLEMENTED: 环节 2B 判断新增、覆盖、删除(sql/30_ingest.sql PLAN_BATCH)');
BEGIN
  -- ===== 你来写:环节 2B 判断新增、覆盖、删除 =====
  -- 要做什么:读 INGEST.FILE_STATE,决定这一批(batch_id = :p_batch_id)每一行接下来怎么办,改 status;
  --           把删除和被覆盖的旧版本在 CORE.CHUNKS 里的块删掉(按 relative_path + etag)。
  -- 输入:这一批 status = 'PENDING' 的行;以及你决定要重试的以前批次的 FAILED 行。
  -- 输出:要解析、切分的行设为 READY;不用再处理的设为 DONE(或你自己定的状态);都要写 updated_at。
  --       RUN_INGEST 只处理 READY 的行,约定见文件头。
  -- 要想清楚:覆盖在 stream 里是一删一增;同一路径在不同批次里的先后;以前新增失败的文件后来被删了,
  --           还要不要重试;重试几次算够(.harness/context/current-state.md 的未决项)。
  -- 注意(docs/pitfalls.md):块表只做增量 DML;游标定义里看不到过程参数,要用就先赋给局部变量或改用 RESULTSET;
  --       过程里 :rec.字段 不合法,先赋给局部变量。
  -- 验收:docs/hands-on.md 环节 2B(用 TEST_ 开头的假 batch 测,不用连 stream)。
  -- 写完删掉下面这一行。
  RAISE not_implemented;
  -- ===== 到这里 =====

  SELECT COUNT(*) INTO :v_pending_left
    FROM INGEST.FILE_STATE
   WHERE batch_id = :p_batch_id AND status = 'PENDING';
  IF (v_pending_left > 0) THEN
    RAISE pending_left;
  END IF;

  RETURN 'planned ' || p_batch_id;
END;
$$;

CREATE OR REPLACE PROCEDURE INGEST.PARSE_FILE(p_relative_path VARCHAR, p_etag VARCHAR, p_config_name VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
COMMENT = 'medrag v2: parse one file version with AI_PARSE_DOCUMENT into PARSED_DOCS; skips versions already parsed'
AS
$$
DECLARE
  v_ok_count      INTEGER;
  parse_failed    EXCEPTION (-20141, 'PARSE_FILE: no successful parse for this file version; see INGEST.PARSED_DOCS.error_message');
  not_implemented EXCEPTION (-20149, 'NOT_IMPLEMENTED: 环节 3A 解析(sql/30_ingest.sql PARSE_FILE)');
BEGIN
  -- 同一版本之前已经解析成功,就不再解析:解析按页计费(docs/pitfalls.md)。
  SELECT COUNT(*) INTO :v_ok_count
    FROM INGEST.PARSED_DOCS
   WHERE relative_path = :p_relative_path AND etag = :p_etag AND error_message IS NULL;
  IF (v_ok_count > 0) THEN
    RETURN 'SKIPPED: already parsed';
  END IF;

  -- ===== 你来写:环节 3A 解析 =====
  -- 要做什么:用 AI_PARSE_DOCUMENT 解析 @MEDRAG.INGEST.CORPUS_STAGE 上的 :p_relative_path,结果写进 INGEST.PARSED_DOCS 一行,
  --           成功失败都写。解析选项(parse_mode、page_split)取 CORE.PIPELINE_CONFIG 里 :p_config_name 那一行。
  -- 输出:PARSED_DOCS 的列见 sql/11_tables.sql。成功时 error_message 为 NULL、page_count 有值;失败时 error_message 写错误原文。
  --       doc_id 是文件名去掉 .pdf;parse_options 写实际用的选项。
  -- 注意(docs/pitfalls.md、.harness/rules/pipeline-rules.md):不要放进 CTE,优化器会内联,函数被重复调用、重复计费;
  --       用 return_error_details 拿错误原文和页数;TO_FILE 用 stage 名加相对路径。
  -- 要想清楚:以后换了解析参数,已经解析成功的版本要不要重新解析(现在按 (路径, etag) 跳过,不看参数)。
  -- 验收:docs/hands-on.md 环节 3A。这一步花钱,真的调用之前先说一声。
  -- 写完删掉下面这一行。
  RAISE not_implemented;
  -- ===== 到这里 =====

  -- 你的代码跑完,还没有成功的行,就抛异常,让 RUN_INGEST 把 FILE_STATE 标成 FAILED。
  SELECT COUNT(*) INTO :v_ok_count
    FROM INGEST.PARSED_DOCS
   WHERE relative_path = :p_relative_path AND etag = :p_etag AND error_message IS NULL;
  IF (v_ok_count = 0) THEN
    RAISE parse_failed;
  END IF;

  RETURN 'PARSED';
END;
$$;
