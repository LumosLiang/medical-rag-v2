-- 单篇切分验收:用任一配置切固定快照里的一篇文档,再逐块查看。
-- 只写这一篇、这个配置的块(CHUNK_DOC 对同版本同配置先删后写),不碰别的配置。
-- 前提:src/sql/ingest/chunk/ 下的过程已部署。改下面三个 SET 即可换文档或配置。
USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;
USE WAREHOUSE MEDICAL_RAG_PARSE_WH;

SET snapshot_name = 'corpus_2026_10_03';
SET doc_id        = 'PMC12681061';
SET config_name   = 'markdown_header_table_1200_200';  -- 或 recursive_once_1200_200

EXECUTE IMMEDIATE $$
DECLARE
  v_path  VARCHAR;
  v_etag  VARCHAR;
  v_count INTEGER;
BEGIN
  SELECT relative_path, etag
    INTO :v_path, :v_etag
    FROM EVAL.CORPUS_FILES
   WHERE snapshot_name = $snapshot_name
     AND doc_id = $doc_id;
  CALL CORE.CHUNK_DOC(:v_path, :v_etag, $config_name, 'MEDRAG.CORE.CHUNKS') INTO :v_count;
  RETURN v_count;
END;
$$;

-- 每一块的章节、页码(从 0 起)、token 数和完整原文。
SELECT chunk_index, section_path, page_start, page_end, token_count, chunk_text_raw
  FROM CORE.CHUNKS
 WHERE config_name = $config_name
   AND doc_id = $doc_id
 ORDER BY chunk_index;
