-- 入库只用 is_active = TRUE 的配置。换切分策略时新建配置名，旧块仍能追溯。
-- chunk_method=recursive_baseline / recursive 对应 CORE.CHUNK_RECURSIVE_BASELINE / CORE.CHUNK_RECURSIVE。
USE ROLE MEDRAG_ADMIN;
USE SCHEMA MEDRAG.CORE;

-- 保留已经部署的列；其中 split_headers、drop_reference_sections、add_prefix
-- 是早期实验留下的字段，当前 recursive 策略不使用。
CREATE TABLE IF NOT EXISTS PIPELINE_CONFIG (
  config_name              VARCHAR       NOT NULL,
  parse_mode               VARCHAR       NOT NULL,
  page_split               BOOLEAN       NOT NULL,
  split_headers            OBJECT        NOT NULL,
  chunk_size_chars         NUMBER        NOT NULL,
  chunk_overlap_chars      NUMBER        NOT NULL,
  max_tokens               NUMBER        NOT NULL,
  token_model              VARCHAR       NOT NULL,
  resplit_chunk_size_chars NUMBER        NOT NULL,
  drop_reference_sections  BOOLEAN       NOT NULL,
  add_prefix               BOOLEAN       NOT NULL,
  is_active                BOOLEAN       NOT NULL,
  note                     VARCHAR,
  created_at               TIMESTAMP_LTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
  CONSTRAINT pk_pipeline_config PRIMARY KEY (config_name)
);

-- 兼容旧环境：这两列可能尚未创建。
ALTER TABLE PIPELINE_CONFIG ADD COLUMN IF NOT EXISTS chunk_method VARCHAR;
ALTER TABLE PIPELINE_CONFIG ADD COLUMN IF NOT EXISTS split_format VARCHAR;
UPDATE PIPELINE_CONFIG
   SET chunk_method = COALESCE(chunk_method, 'markdown_header'),
       split_format = COALESCE(split_format, 'none')
 WHERE chunk_method IS NULL OR split_format IS NULL;

-- 已部署的旧配置及其历史块保留，不改名、不改参数。
INSERT INTO PIPELINE_CONFIG (
  config_name, parse_mode, page_split, split_headers, chunk_size_chars,
  chunk_overlap_chars, max_tokens, token_model, resplit_chunk_size_chars,
  drop_reference_sections, add_prefix, is_active, note, chunk_method, split_format
)
SELECT 'recursive_1200_200', 'LAYOUT', TRUE, OBJECT_CONSTRUCT(), 1200,
       200, 512, 'snowflake-arctic-embed-l-v2.0', 1000,
       FALSE, FALSE, FALSE, 'Repeatedly resplit chunks over 512 tokens', 'recursive', 'none'
 WHERE NOT EXISTS (
   SELECT 1 FROM PIPELINE_CONFIG WHERE config_name = 'recursive_1200_200'
 );

-- 名称说明算法和参数：只切一次，1200 字符，200 字符 overlap。
INSERT INTO PIPELINE_CONFIG (
  config_name, parse_mode, page_split, split_headers, chunk_size_chars,
  chunk_overlap_chars, max_tokens, token_model, resplit_chunk_size_chars,
  drop_reference_sections, add_prefix, is_active, note, chunk_method, split_format
)
SELECT 'recursive_once_1200_200', 'LAYOUT', TRUE, OBJECT_CONSTRUCT(), 1200,
       200, 512, 'snowflake-arctic-embed-l-v2.0', 1000,
       FALSE, FALSE, FALSE, 'One recursive split; token_count is observational', 'recursive_baseline', 'none'
 WHERE NOT EXISTS (
   SELECT 1 FROM PIPELINE_CONFIG WHERE config_name = 'recursive_once_1200_200'
 );

-- 补切版：初次 1200/200，超出 512 token 时继续补切；旧配置保留供追溯。
INSERT INTO PIPELINE_CONFIG (
  config_name, parse_mode, page_split, split_headers, chunk_size_chars,
  chunk_overlap_chars, max_tokens, token_model, resplit_chunk_size_chars,
  drop_reference_sections, add_prefix, is_active, note, chunk_method, split_format
)
SELECT 'recursive_resplit_to_512_tokens_1200_200', 'LAYOUT', TRUE, OBJECT_CONSTRUCT(), 1200,
       200, 512, 'snowflake-arctic-embed-l-v2.0', 1000,
       FALSE, FALSE, FALSE, 'Repeatedly resplit chunks over 512 tokens', 'recursive', 'none'
 WHERE NOT EXISTS (
   SELECT 1 FROM PIPELINE_CONFIG WHERE config_name = 'recursive_resplit_to_512_tokens_1200_200'
 );

-- 每次部署只切换 active，不改任何已存在配置的参数或历史块。
UPDATE PIPELINE_CONFIG
   SET is_active = (config_name = 'recursive_once_1200_200')
 WHERE is_active OR config_name = 'recursive_once_1200_200';
