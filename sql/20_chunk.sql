-- 切分过程。入库和评测实验共用这一份切分逻辑:入库时写 CORE.CHUNKS,评测实验传自己的表。
-- 由 deploy.sql 调用,可以重复执行(过程用 CREATE OR REPLACE 更新;改签名要先 DROP,见 docs/pitfalls.md)。
--
-- 用法:CALL MEDRAG.CORE.CHUNK_DOC('<relative_path>', '<etag>', '<config_name>', 'MEDRAG.CORE.CHUNKS');
-- 返回写入的块数。任何一步出错都抛异常,这个版本的块回到调用前的样子。

USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

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
  missing_config  EXCEPTION (-20111, 'CHUNK_DOC: config not found in CORE.PIPELINE_CONFIG');
  missing_parse   EXCEPTION (-20112, 'CHUNK_DOC: this file version has no successful row in INGEST.PARSED_DOCS');
  not_implemented EXCEPTION (-20119, 'NOT_IMPLEMENTED: 环节 5A 切分(sql/20_chunk.sql)');
BEGIN
  SELECT COUNT(*) INTO :v_config_count
    FROM CORE.PIPELINE_CONFIG
   WHERE config_name = :p_config_name;
  IF (v_config_count = 0) THEN
    RAISE missing_config;
  END IF;

  SELECT COUNT(*) INTO :v_parsed_count
    FROM INGEST.PARSED_DOCS
   WHERE relative_path = :p_relative_path
     AND etag = :p_etag
     AND error_message IS NULL;
  IF (v_parsed_count = 0) THEN
    RAISE missing_parse;
  END IF;

  -- 删旧块和写新块在一个事务里:中途出错就回滚,检索服务不会看到这个版本只剩一半块。
  BEGIN TRANSACTION;

  -- 同一版本、同一配置重跑时,先删掉上次的块,保证可以重复执行。
  DELETE FROM IDENTIFIER(:p_target_table)
   WHERE relative_path = :p_relative_path
     AND etag = :p_etag
     AND config_name = :p_config_name;

  -- ===== 你来写:环节 5A 切分 =====
  -- 要做什么:把这个版本的解析结果切成块,写进 IDENTIFIER(:p_target_table)。四步见 .harness/rules/pipeline-rules.md:
  --   1. SPLIT_TEXT_MARKDOWN_HEADER 按配置的 split_headers、chunk_size_chars、chunk_overlap_chars 切;
  --   2. drop_reference_sections 为 TRUE 时丢掉参考文献章节;add_prefix 为 TRUE 时在 chunk_text 前加"标题 > 章节";
  --   3. SNOWFLAKE.CORTEX.COUNT_TOKENS(token_model, chunk_text) 数 token;
  --   4. 超过 max_tokens 的块用 SPLIT_TEXT_RECURSIVE_CHARACTER(resplit_chunk_size_chars)再切,再数一次。
  -- 输入:INGEST.PARSED_DOCS 里 relative_path = :p_relative_path、etag = :p_etag、error_message IS NULL 的那一行
  --       (parse_result 是 AI_PARSE_DOCUMENT 的原样输出);CORE.PIPELINE_CONFIG 里 config_name = :p_config_name 的那一行。
  -- 输出:目标表的列同 CORE.CHUNKS(sql/11_tables.sql),config_name 填 :p_config_name。
  -- 硬性要求:每块 token_count <= max_tokens;没有空块;没有参考文献章节;chunk_id 唯一、由确定的输入生成、重跑不变。
  -- 注意(docs/pitfalls.md):RLIKE 是整串匹配;AI_COUNT_TOKENS 对 embedding 模型返回 NULL;
  --       过程里 :rec.字段 不合法,先赋给局部变量。
  -- 要想清楚:pages 先拼起来再切,还是按页切;chunk_id 用什么拼;前缀里的文档标题从哪来。
  -- 验收:docs/hands-on.md 环节 5A。
  -- 写完删掉下面这一行。
  RAISE not_implemented;
  -- ===== 到这里 =====

  COMMIT;

  SELECT COUNT(*) INTO :v_chunk_count
    FROM IDENTIFIER(:p_target_table)
   WHERE relative_path = :p_relative_path
     AND etag = :p_etag
     AND config_name = :p_config_name;
  RETURN v_chunk_count;
EXCEPTION
  WHEN OTHER THEN
    ROLLBACK;
    RAISE;
END;
$$;
