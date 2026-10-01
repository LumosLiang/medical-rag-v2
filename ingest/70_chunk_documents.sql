-- 切分:把一个解析好的文件版本切成块,写进块表。块表 CORE.CHUNKS 是检索服务的源表。
-- 入库和评测实验共用这一份切分逻辑:入库时写 CORE.CHUNKS,评测实验传自己的表。
-- 由 deploy.sql 调用,可以重复执行:表已经存在就不动;过程用 CREATE OR REPLACE 更新(改签名要先 DROP,见 docs/pitfalls.md)。
--
-- 在流程里的位置:RUN_INGEST(80_run_ingest.sql)解析完一个版本(60_parse_documents.sql)就调 CHUNK_DOC。
-- 用法:CALL MEDRAG.CORE.CHUNK_DOC('<relative_path>', '<etag>', '<config_name>', 'MEDRAG.CORE.CHUNKS');
-- 返回写入的块数。任何一步出错都抛异常,这个版本的块回到调用前的样子。
--
-- 以后加列:在 CREATE TABLE 后面写 ALTER TABLE ... ADD COLUMN IF NOT EXISTS;只改 CREATE TABLE 本身不会影响已经部署的表。
-- CHUNKS 的列要在环节 7 建检索服务之前定下来:服务建好后再改 source query 的列,会触发全量重新 embedding(docs/pitfalls.md)。

USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

-- test



-- 检索服务的源表。只做增量 DML(INSERT、DELETE、MERGE),不重建、不整表删了重插。
CREATE TABLE IF NOT EXISTS CORE.CHUNKS (
  chunk_id       VARCHAR       NOT NULL COMMENT 'Unique, built from deterministic inputs, stable across reruns; search service primary key',
  doc_id         VARCHAR       NOT NULL,
  relative_path  VARCHAR       NOT NULL,
  etag           VARCHAR       NOT NULL COMMENT 'File version the chunk came from; must be the current version',
  config_name    VARCHAR       NOT NULL COMMENT 'PIPELINE_CONFIG used to chunk it',
  chunk_index    NUMBER        NOT NULL COMMENT 'Order within the document, starting at 0',
  section_path   VARCHAR       COMMENT 'Header path, e.g. Results > Survival',
  chunk_text     VARCHAR       NOT NULL COMMENT 'Indexed text, with prefix',
  chunk_text_raw VARCHAR       NOT NULL COMMENT 'Original text, for display and evidence matching',
  token_count    NUMBER        NOT NULL COMMENT 'Tokens in chunk_text, measured with COUNT_TOKENS',
  page_start     NUMBER        COMMENT 'Starting at 0; NULL when pages cannot be matched',
  page_end       NUMBER,
  created_at     TIMESTAMP_LTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
  CONSTRAINT pk_chunks PRIMARY KEY (chunk_id)
)
CHANGE_TRACKING = TRUE
COMMENT = 'medrag v2: indexed chunks; incremental DML only';

-- 表已存在时 CREATE 不会生效,这里再确认一次 change tracking 是开的(Cortex Search 需要)。
ALTER TABLE CORE.CHUNKS SET CHANGE_TRACKING = TRUE;

CREATE OR REPLACE PROCEDURE CORE.CHUNK_DOC(
  p_relative_path VARCHAR,
  p_etag          VARCHAR,
  p_config_name   VARCHAR,
  p_target_table  VARCHAR
)
RETURNS NUMBER
LANGUAGE SQL
COMMENT = 'medrag v2: chunk one parsed file version with one config into the target table'
EXECUTE AS OWNER
AS
$$
DECLARE
  v_config_count INTEGER;
  v_parsed_count INTEGER;
  v_chunk_count  INTEGER;
  v_bad_count    INTEGER;
  v_format       VARCHAR;
  v_chunk_size   INTEGER;
  v_overlap      INTEGER;
  v_resplit_size INTEGER;
  v_max_tokens   INTEGER;
  v_token_model  VARCHAR;
  v_method       VARCHAR;
  missing_config EXCEPTION (-20111, 'CHUNK_DOC: config not found in CORE.PIPELINE_CONFIG');
  missing_parse  EXCEPTION (-20112, 'CHUNK_DOC: this file version has no successful row in INGEST.PARSED_DOCS');
  wrong_method   EXCEPTION (-20113, 'CHUNK_DOC: config must use recursive chunking');
  invalid_chunks EXCEPTION (-20114, 'CHUNK_DOC: no chunks, or a chunk still exceeds max_tokens');
BEGIN
  -- 先取这次切分的配置；后面的 SQL 都用同一组参数。
  SELECT COUNT(*) INTO :v_config_count
    FROM CORE.PIPELINE_CONFIG
   WHERE config_name = :p_config_name;
  IF (v_config_count = 0) THEN
    RAISE missing_config;
  END IF;

  -- 读配置参数:split_format、chunk_size_chars、chunk_overlap_chars、resplit_chunk_size_chars、max_tokens、token_model、chunk_method。
  SELECT split_format, chunk_size_chars, chunk_overlap_chars,
         resplit_chunk_size_chars, max_tokens, token_model, chunk_method
    INTO :v_format, :v_chunk_size, :v_overlap,
         :v_resplit_size, :v_max_tokens, :v_token_model, :v_method
    FROM CORE.PIPELINE_CONFIG
   WHERE config_name = :p_config_name;
  IF (v_method <> 'recursive') THEN
    RAISE wrong_method;
  END IF;

  -- 只处理已经解析成功的这个文件版本，不重新调用 AI_PARSE_DOCUMENT。
  SELECT COUNT(*) INTO :v_parsed_count
    FROM INGEST.PARSED_DOCS
   WHERE relative_path = :p_relative_path
     AND etag = :p_etag
     AND error_message IS NULL;
  IF (v_parsed_count = 0) THEN
    RAISE missing_parse;
  END IF;

  -- 同版本、同配置重跑时先删后写；失败则一起回滚。
  BEGIN TRANSACTION;
  DELETE FROM IDENTIFIER(:p_target_table)
   WHERE relative_path = :p_relative_path
     AND etag = :p_etag
     AND config_name = :p_config_name;

  -- 数据流：解析后的页 → 初次切块 → 超 token 的块再切 → 排序编号 → 写表。
  INSERT INTO IDENTIFIER(:p_target_table) (
    chunk_id, doc_id, relative_path, etag, config_name, chunk_index,
    section_path, chunk_text, chunk_text_raw, token_count, page_start, page_end
  )
  -- first_pass：FLATTEN 把 pages 展开成行，再把每页切成多行；piece.index 是页内顺序。
  -- recursive 函数省略 separators，使用 Snowflake 默认分隔符。
  WITH first_pass AS (
    SELECT p.doc_id,
           page.value:index::NUMBER AS page_index,
           piece.index AS piece_index,
           piece.value::VARCHAR AS chunk_text,
           SNOWFLAKE.CORTEX.COUNT_TOKENS(:v_token_model, piece.value::VARCHAR) AS token_count
      FROM INGEST.PARSED_DOCS p,
           LATERAL FLATTEN(input => p.parse_result:value:pages) page,
           LATERAL FLATTEN(input => SNOWFLAKE.CORTEX.SPLIT_TEXT_RECURSIVE_CHARACTER(
             page.value:content::VARCHAR, :v_format, :v_chunk_size, :v_overlap
           )) piece
     WHERE p.relative_path = :p_relative_path
       AND p.etag = :p_etag
       AND p.error_message IS NULL
  ),
  -- final_pass：未超限的块原样保留；超限的块用较小尺寸再切一次。
  -- IFF 的两边都返回 ARRAY，FLATTEN 再把最终块展开成行。
  final_pass AS (
    SELECT f.doc_id, f.page_index, f.piece_index, smaller.index AS smaller_index,
           smaller.value::VARCHAR AS chunk_text
      FROM first_pass f,
           LATERAL FLATTEN(input => IFF(
             f.token_count > :v_max_tokens,
             SNOWFLAKE.CORTEX.SPLIT_TEXT_RECURSIVE_CHARACTER(
               f.chunk_text, :v_format, :v_resplit_size, :v_overlap
             ),
             ARRAY_CONSTRUCT(f.chunk_text)
           )) smaller
  ),
  -- 排序chunk：去掉空白块，按页码和两次切分的顺序生成从 0 开始的 chunk_index。 减1是因为 ROW_NUMBER() 从 1 开始。
  numbered AS (
    SELECT doc_id, page_index, chunk_text,
           ROW_NUMBER() OVER (ORDER BY page_index, piece_index, smaller_index) - 1 AS chunk_index
      FROM final_pass
     WHERE NULLIF(TRIM(chunk_text), '') IS NOT NULL
  )
  -- 同一文件版本、配置和顺序生成相同 chunk_id；当前无前缀，原文和索引文本相同。
    -- sha2是为了生成唯一的chunk_id，确保即使在不同环境或时间运行相同的输入也会得到相同的输出
  SELECT SHA2(:p_relative_path || '|' || :p_etag || '|' || :p_config_name || '|' || chunk_index::VARCHAR, 256),
         doc_id, :p_relative_path, :p_etag, :p_config_name, chunk_index,
         NULL, chunk_text, chunk_text,
         SNOWFLAKE.CORTEX.COUNT_TOKENS(:v_token_model, chunk_text),
         page_index, page_index
    FROM numbered;

  -- 字符数不保证 token 数；超限或没有块时回滚。
  SELECT COUNT(*), COUNT_IF(token_count IS NULL OR token_count > :v_max_tokens)
    INTO :v_chunk_count, :v_bad_count
    FROM IDENTIFIER(:p_target_table)
   WHERE relative_path = :p_relative_path
     AND etag = :p_etag
     AND config_name = :p_config_name;
  IF (v_chunk_count = 0 OR v_bad_count > 0) THEN
    RAISE invalid_chunks;
  END IF;

  COMMIT;
  RETURN v_chunk_count;
EXCEPTION
  WHEN OTHER THEN
    ROLLBACK;
    RAISE;
END;
$$;

-- call CORE.CHUNK_DOC('PMC10275696.pdf', '"0x8DF1DFD5260DBC0"', 'recursive_1200_200', 'MEDRAG.CORE.CHUNKS');
