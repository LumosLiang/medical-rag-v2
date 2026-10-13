-- 历史配置使用 chunk_method=markdown_header_table；保留旧入口以继续读取既有实验与块。
-- 算法只在 CHUNK_STRUCTURED_MARKDOWN 中实现。新配置可直接用 chunk_method=structured_markdown。
USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

CREATE OR REPLACE PROCEDURE CORE.CHUNK_MARKDOWN_HEADER_TABLE(
  p_relative_path VARCHAR,
  p_etag VARCHAR,
  p_config_name VARCHAR,
  p_target_table VARCHAR,
  p_format VARCHAR,
  p_chunk_size INTEGER,
  p_overlap INTEGER,
  p_token_model VARCHAR,
  p_resplit_size INTEGER,
  p_max_tokens INTEGER
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
  v_result VARCHAR;
BEGIN
  CALL CORE.CHUNK_STRUCTURED_MARKDOWN(:p_relative_path, :p_etag, :p_config_name, :p_target_table, :p_format, :p_chunk_size, :p_overlap, :p_token_model, :p_resplit_size, :p_max_tokens) INTO :v_result;
  RETURN v_result;
END;
$$;
