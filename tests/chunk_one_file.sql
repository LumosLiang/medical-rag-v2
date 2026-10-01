-- 单文件切分验收。先部署 ingest/10 和 ingest/70，再在 Snowflake 里单独运行本文件。
-- 文件名可换成 DIRECTORY(@MEDRAG.INGEST.CORPUS_STAGE) 中已有且 PARSED_DOCS 已解析成功的 PDF。
USE ROLE MEDRAG_ADMIN;
USE WAREHOUSE MEDICAL_RAG_PARSE_WH;
USE DATABASE MEDRAG;

-- LATERAL FLATTEN 练习：下面两段 SELECT 分别选中运行，只读，不写入 CHUNKS。
-- 官方语法：https://docs.snowflake.com/en/sql-reference/functions/flatten
-- FLATTEN 把数组拆成多行；LATERAL 让它能读取左边 p 这一行的数据。
-- page 是展开结果的别名；page.index 是数组位置，page.value 是该位置的内容。

-- 练习 1：把 pages 数组展开成每页一行。可把 page_preview 换成 page.value 看完整对象。
SELECT p.relative_path,
       page.index AS array_index,
       page.value:index::NUMBER AS page_number,
      --  LEFT(page.value:content::VARCHAR, 200) AS page_preview
      page.value:content::VARCHAR AS page_content
  FROM INGEST.PARSED_DOCS p,
       LATERAL FLATTEN(input => p.parse_result:value:pages) page
 WHERE p.relative_path = 'PMC10275696.pdf'
   AND p.etag = (SELECT etag FROM DIRECTORY(@MEDRAG.INGEST.CORPUS_STAGE)
                WHERE relative_path = 'PMC10275696.pdf')
   AND p.error_message IS NULL
 ORDER BY page.index;

-- 练习 2：先展开页面，再把第一页切出的数组展开成每块一行。
-- 第二个 FLATTEN 能读取左边 page.value；piece.value 就是一块文本。
-- 可把 page.index = 0 改成 1，看第二页；也可调整 1200 和 200 看切分变化。
SELECT page.value:index::NUMBER AS page_number,
       piece.index AS piece_index,
       LENGTH(piece.value::VARCHAR) AS char_count,
       piece.value::VARCHAR AS chunk_text
  FROM INGEST.PARSED_DOCS p,
       LATERAL FLATTEN(input => p.parse_result:value:pages) page,
       LATERAL FLATTEN(input => SNOWFLAKE.CORTEX.SPLIT_TEXT_RECURSIVE_CHARACTER(
         page.value:content::VARCHAR, 'none', 1200, 200
       )) piece
 WHERE p.relative_path = 'PMC10275696.pdf'
   AND p.etag = (SELECT etag FROM DIRECTORY(@MEDRAG.INGEST.CORPUS_STAGE)
                WHERE relative_path = 'PMC10275696.pdf')
   AND p.error_message IS NULL
   AND page.index = 0
 ORDER BY piece.index;

-- 以下是原来的切分验收，需要先部署 CHUNK_DOC；上面的练习不需要。
EXECUTE IMMEDIATE $$
DECLARE
  v_path  VARCHAR DEFAULT 'PMC10275696.pdf';
  v_etag  VARCHAR;
  v_count NUMBER;
BEGIN
  SELECT etag INTO :v_etag
    FROM DIRECTORY(@MEDRAG.INGEST.CORPUS_STAGE)
   WHERE relative_path = :v_path;
  CALL CORE.CHUNK_DOC(:v_path, :v_etag, 'recursive_1200_200', 'MEDRAG.CORE.CHUNKS') INTO :v_count;
  RETURN 'chunked ' || v_path || ': ' || v_count::VARCHAR || ' chunks';
END;
$$;

-- 验收：超 512 token、空块、重复 ID 都应为 0。
SELECT COUNT(*) AS chunk_count,
       COALESCE(COUNT_IF(token_count > 512 OR token_count IS NULL), 0) AS over_limit,
       COALESCE(COUNT_IF(NULLIF(TRIM(chunk_text), '') IS NULL), 0) AS empty_chunks,
       COUNT(*) - COUNT(DISTINCT chunk_id) AS duplicate_ids
  FROM CORE.CHUNKS
 WHERE relative_path = 'PMC10275696.pdf'
   AND etag = (SELECT etag FROM DIRECTORY(@MEDRAG.INGEST.CORPUS_STAGE)
                WHERE relative_path = 'PMC10275696.pdf')
   AND config_name = 'recursive_1200_200';

-- 看每一块的完整文本、页码和 token 数。这个 SELECT 的结果就是你要看的切分效果。
SELECT chunk_index, page_start, token_count, LENGTH(chunk_text) AS char_count, chunk_text
  FROM CORE.CHUNKS
 WHERE relative_path = 'PMC10275696.pdf'
   AND etag = (SELECT etag FROM DIRECTORY(@MEDRAG.INGEST.CORPUS_STAGE)
                WHERE relative_path = 'PMC10275696.pdf')
   AND config_name = 'recursive_1200_200'
 ORDER BY chunk_index;
