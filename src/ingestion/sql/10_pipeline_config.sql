-- PIPELINE_CONFIG 保存可复现的解析与切分参数；config_name 同时标识 CHUNKS 中的一组结果。
-- 各策略复用 LAYOUT 逐页解析；算法参数、token 模型与窗口按配置固定。
-- is_active 只选择日常入库策略；实验可显式使用其他配置，不改变日常入库。
USE ROLE MEDRAG_ADMIN;
USE SCHEMA MEDRAG.CORE;

CREATE TABLE IF NOT EXISTS PIPELINE_CONFIG (
  config_name              VARCHAR       NOT NULL,
  parse_mode               VARCHAR       NOT NULL,
  page_split               BOOLEAN       NOT NULL,
  chunk_method             VARCHAR       NOT NULL,
  split_format             VARCHAR       NOT NULL,
  split_headers            OBJECT        NOT NULL,
  chunk_size_chars         NUMBER        NOT NULL,
  chunk_overlap_chars      NUMBER        NOT NULL,
  max_tokens               NUMBER        NOT NULL,
  token_model              VARCHAR       NOT NULL,
  resplit_chunk_size_chars NUMBER        NOT NULL,
  -- 历史标志保留兼容；结构化策略的实际开关统一放在 method_options。
  drop_reference_sections  BOOLEAN       NOT NULL,
  add_prefix               BOOLEAN       NOT NULL,
  is_active                BOOLEAN       NOT NULL,
  note                     VARCHAR,
  method_options          OBJECT,
  created_at               TIMESTAMP_LTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
  CONSTRAINT pk_pipeline_config PRIMARY KEY (config_name)
);

-- 为已有表补齐算法选择列；只补已知配置，不给未知配置猜一个算法。
ALTER TABLE PIPELINE_CONFIG ADD COLUMN IF NOT EXISTS method_options OBJECT;
ALTER TABLE PIPELINE_CONFIG ADD COLUMN IF NOT EXISTS chunk_method VARCHAR;
ALTER TABLE PIPELINE_CONFIG ADD COLUMN IF NOT EXISTS split_format VARCHAR;
UPDATE PIPELINE_CONFIG
   SET chunk_method = COALESCE(chunk_method,
         CASE config_name
           WHEN 'recursive_1200_200' THEN 'recursive'
           WHEN 'recursive_once_1200_200' THEN 'recursive_baseline'
           WHEN 'recursive_resplit_to_512_tokens_1200_200' THEN 'recursive'
           WHEN 'markdown_header_table_1200_200' THEN 'markdown_header_table'
         END),
       split_format = COALESCE(split_format,
         IFF(config_name = 'markdown_header_table_1200_200', 'markdown', 'none'))
 WHERE (chunk_method IS NULL OR split_format IS NULL)
   AND config_name IN ('recursive_1200_200', 'recursive_once_1200_200',
       'recursive_resplit_to_512_tokens_1200_200', 'markdown_header_table_1200_200');

-- 共用参数只定义一次，策略表只列出不同项。已存在的配置参数保持不变。
-- 历史 recursive_1200_200 及其块仍可使用，但新环境不再创建这个重复的配置别名。
INSERT INTO PIPELINE_CONFIG (
  config_name, parse_mode, page_split, chunk_method, split_format, split_headers,
  chunk_size_chars, chunk_overlap_chars, max_tokens, token_model,
  resplit_chunk_size_chars, drop_reference_sections, add_prefix, is_active, note
)
WITH strategies AS (
  SELECT 'recursive_once_1200_200' AS config_name,
         'recursive_baseline' AS chunk_method, 'none' AS split_format,
         OBJECT_CONSTRUCT() AS split_headers,
         'One recursive split; token_count is observational' AS note
  UNION ALL
  SELECT 'recursive_resplit_to_512_tokens_1200_200', 'recursive', 'none',
         OBJECT_CONSTRUCT(), 'Recursive split with token-limited resplitting'
  UNION ALL
  SELECT 'markdown_header_table_1200_200', 'markdown_header_table', 'markdown',
         OBJECT_CONSTRUCT('#', 'h1', '##', 'h2', '###', 'h3'),
         'Section and table chunks; table target 450 tokens; oversized chunks resplit'
)
SELECT s.config_name, 'LAYOUT', TRUE, s.chunk_method, s.split_format, s.split_headers,
       1200, 200, 512, 'snowflake-arctic-embed-l-v2.0',
       1000, FALSE, FALSE, FALSE, s.note
  FROM strategies s
 WHERE NOT EXISTS (SELECT 1 FROM PIPELINE_CONFIG c WHERE c.config_name = s.config_name);

-- 只有尚未选定日常策略时才初始化基线；重复部署不覆盖用户已选的 active 配置。
UPDATE PIPELINE_CONFIG
   SET is_active = TRUE
 WHERE config_name = 'recursive_once_1200_200'
   AND NOT EXISTS (SELECT 1 FROM PIPELINE_CONFIG WHERE is_active);

-- 8K 实验：正文约 1024 token，摘要/表格允许接近完整模型窗口。
-- 4096/600 是原生 splitter 的字符参数；正文另有精确 token 目标，不假定固定字符/token 比例。
INSERT INTO PIPELINE_CONFIG (
  config_name, parse_mode, page_split, chunk_method, split_format, split_headers,
  chunk_size_chars, chunk_overlap_chars, max_tokens, token_model,
  resplit_chunk_size_chars, drop_reference_sections, add_prefix, is_active, method_options, note
)
SELECT 'structured_markdown_8k_body_1024', 'LAYOUT', TRUE, 'structured_markdown', 'markdown',
       OBJECT_CONSTRUCT('#', 'h1', '##', 'h2', '###', 'h3'),
       4096, 600, 8192, 'snowflake-arctic-embed-l-v2.0-8k',
       4096, TRUE, FALSE, FALSE,
       OBJECT_CONSTRUCT('body_target_tokens', 1024, 'table_target_tokens', 8000,
         'preserve_abstract', TRUE, 'drop_reference_sections', TRUE,
         'drop_publication_noise', TRUE, 'attach_table_notes', TRUE),
       '8K model; body target 1024 tokens; full abstracts/tables when within window; conservative noise removal'
 WHERE NOT EXISTS (SELECT 1 FROM PIPELINE_CONFIG WHERE config_name = 'structured_markdown_8k_body_1024');
