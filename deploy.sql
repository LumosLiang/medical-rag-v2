--!jinja
-- 建立入库过程与检索服务；只部署对象定义，不执行回填或检索实验。
-- 初始资源由 infra/snowflake/setup/ 建立，评测对象由 eval/deploy.sql 独立部署。

USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;
USE WAREHOUSE MEDICAL_RAG_INDEX_WH;

EXECUTE IMMEDIATE FROM './src/ingestion/sql/10_pipeline_config.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/20_corpus_stage_and_stream.sql' USING (stage_base_url => '{{ stage_base_url }}');
EXECUTE IMMEDIATE FROM './src/ingestion/sql/30_capture_file_changes.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/40_classify_file_changes.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/50_remove_old_chunks.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/60_parse_documents.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/chunk/schema.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/chunk/chunk_doc.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/chunk/strategies/recursive_baseline.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/chunk/strategies/recursive_token_limited.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/chunk/strategies/structured_markdown/document/normalize_pages.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/chunk/strategies/structured_markdown/tables/extract_elements.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/chunk/strategies/structured_markdown/tables/build_table_chunks.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/chunk/strategies/structured_markdown/annotate_chunks.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/chunk/strategies/structured_markdown/document/prepare_document.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/chunk/strategies/structured_markdown/document/split_abstract_spans.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/chunk/strategies/structured_markdown/tables/attach_notes.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/chunk/strategies/structured_markdown/chunk_document.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/chunk/strategies/structured_markdown/compatibility.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/80_run_ingest.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/90_ingest_task.sql';
EXECUTE IMMEDIATE FROM './src/serving/cortex_search/recursive.sql';
EXECUTE IMMEDIATE FROM './src/serving/cortex_search/structured_markdown/body.sql';
EXECUTE IMMEDIATE FROM './src/serving/cortex_search/structured_markdown/heading_prefix.sql';
EXECUTE IMMEDIATE FROM './src/serving/cortex_search/structured_markdown/multi_index.sql';
EXECUTE IMMEDIATE FROM './src/serving/cortex_search/structured_markdown/arctic_8k_control.sql';
EXECUTE IMMEDIATE FROM './src/serving/cortex_search/structured_markdown/arctic_8k_large.sql';
