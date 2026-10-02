-- 手工运行一次：新切分过程部署后，把当前已完成、已解析的文件补成基线块。
-- 不在 deploy.sql 中执行；同文件同配置重跑会替换块。FAILED 文件另走 RUN_INGEST 重试。
USE ROLE MEDRAG_ADMIN;
USE WAREHOUSE MEDICAL_RAG_PARSE_WH;
USE DATABASE MEDRAG;

EXECUTE IMMEDIATE $$
DECLARE
  v_path VARCHAR;
  v_etag VARCHAR;
  v_written NUMBER;
  v_files NUMBER DEFAULT 0;
  current_files CURSOR FOR
    SELECT DISTINCT p.relative_path, p.etag
      FROM INGEST.PARSED_DOCS p
      JOIN DIRECTORY(@INGEST.CORPUS_STAGE) d
        ON p.relative_path = d.relative_path AND p.etag = d.etag
      JOIN INGEST.FILE_CHANGES f
        ON p.relative_path = f.relative_path AND p.etag = f.etag
     WHERE p.error_message IS NULL
       AND f.status = 'DONE';
BEGIN
  FOR file_row IN current_files DO
    v_path := file_row.relative_path;
    v_etag := file_row.etag;
    CALL CORE.CHUNK_DOC(:v_path, :v_etag,
      'recursive_once_1200_200', 'MEDRAG.CORE.CHUNKS') INTO :v_written;
    v_files := v_files + 1;
  END FOR;
  RETURN v_files;
END;
$$;

SELECT COUNT(*) AS baseline_chunks, COUNT(DISTINCT relative_path) AS baseline_files
  FROM CORE.CHUNKS
 WHERE config_name = 'recursive_once_1200_200';
