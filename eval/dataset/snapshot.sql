-- 语料快照:给当前 stage 上的每个 PDF 算 sha256,用 pypdf 抽出每页的文字层,写进 EVAL.CORPUS_FILES 和 EVAL.PDF_PAGES。
-- 用法:CALL MEDRAG.EVAL.SNAPSHOT_CORPUS('<snapshot_name>');一个快照名只能做一次,语料变了就用新名字。
--
-- 为什么不用 INGEST.PARSED_DOCS:那是 AI_PARSE_DOCUMENT 的输出,换解析方式就会变。
-- 这里用 PDF 自带的文字层,工具和版本写死(pypdf 6.8.0)。文字层只用来辅助出题和定位证据;
-- 最终依据是审核时在 PDF 上核对过的证据(.harness/rules/eval-rules.md)。
-- PDF_PAGES 当前按 sha256 缓存单一提取器版本；更换工具需隔离结果，不能作为同一次提取复用。

USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

-- 一个文件一次调用:读整个文件 → 算 sha256 → 每页输出一行。
-- 扫描版 PDF 没有文字层,page_text 为空;出题时跳过这种页。
CREATE OR REPLACE FUNCTION EVAL.PDF_PAGES_OF(file_url VARCHAR)
RETURNS TABLE (sha256 VARCHAR, page_number NUMBER, page_count NUMBER, page_text VARCHAR)
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'pypdf==6.8.0')
HANDLER = 'PdfPages'
COMMENT = 'medrag v2 eval: sha256 and per-page text layer of one PDF, extracted with pypdf 6.8.0'
AS
$$
import hashlib
import io

import pypdf
from snowflake.snowpark.files import SnowflakeFile

class PdfPages:
    def process(self, file_url):
        with SnowflakeFile.open(file_url, "rb") as f:
            data = f.read()
        sha256 = hashlib.sha256(data).hexdigest()
        reader = pypdf.PdfReader(io.BytesIO(data))
        page_count = len(reader.pages)
        for i, page in enumerate(reader.pages):
            # 某一页抽不出来不影响其它页;这一页记为空。
            try:
                text = page.extract_text()
            except Exception:
                text = None
            yield (sha256, i + 1, page_count, clean(text))

def clean(text):
    # pypdf 可能给出 UTF-16 代理字符(数学字母符号等),Snowflake 存不了:
    # 成对的合回正常字符,落单的换成 U+FFFD;再去掉 NUL。
    if text is None:
        return None
    text = text.encode("utf-16", "surrogatepass").decode("utf-16", "replace")
    return text.replace("\x00", "")
$$;

-- 定位证据时两边都先做同样的归一化:转小写,只保留 a-z 和 0-9。
-- 这样空白、断词连字符、引号、表格排版不影响定位;代价是符号全被去掉:
-- −6.1 和 6.1、≥5 和 ≤5、1.2 和 12 会变成一样,希腊字母也没了。
-- 所以它只用来找证据在哪一页(草稿核对、页码纠正),不能单独作为答案正确或检索覆盖的评分依据;
-- 评分用的匹配规则随评测过程另定。改这个函数要在 eval-rules.md 里记一笔。
CREATE OR REPLACE FUNCTION EVAL.NORMALIZE_TEXT(s VARCHAR)
RETURNS VARCHAR
COMMENT = 'medrag v2 eval: normalization for locating evidence in the text layer (v2: lowercase, keep only a-z and 0-9); not a scoring rule'
AS
$$
  REGEXP_REPLACE(LOWER(s), '[^a-z0-9]', '')
$$;

-- 证据能否在一页文字层里定位到:有 evidence_parts 时每个片段都要找到,否则看 evidence_text。
-- 空片段算找不到,免得空字符串让 CONTAINS 误报命中。同样只用于定位,不是评分规则。
-- lambda 里不能调用 UDF,所以归一化写成和 NORMALIZE_TEXT 一样的表达式。
CREATE OR REPLACE FUNCTION EVAL.EVIDENCE_LOCATED(
  page_text      VARCHAR,
  evidence_text  VARCHAR,
  evidence_parts ARRAY
)
RETURNS BOOLEAN
COMMENT = 'medrag v2 eval: whether evidence (all evidence_parts, or evidence_text) is located in a text-layer page'
AS
$$
  CASE
    WHEN page_text IS NULL THEN FALSE
    WHEN COALESCE(ARRAY_SIZE(evidence_parts), 0) = 0 THEN
      NULLIF(REGEXP_REPLACE(LOWER(evidence_text), '[^a-z0-9]', ''), '') IS NOT NULL
      AND CONTAINS(REGEXP_REPLACE(LOWER(page_text), '[^a-z0-9]', ''),
                   REGEXP_REPLACE(LOWER(evidence_text), '[^a-z0-9]', ''))
    ELSE ARRAY_SIZE(FILTER(evidence_parts, x ->
           NULLIF(REGEXP_REPLACE(LOWER(x::VARCHAR), '[^a-z0-9]', ''), '') IS NULL
           OR NOT CONTAINS(REGEXP_REPLACE(LOWER(page_text), '[^a-z0-9]', ''),
                           REGEXP_REPLACE(LOWER(x::VARCHAR), '[^a-z0-9]', ''))
         )) = 0
  END
$$;

CREATE OR REPLACE PROCEDURE EVAL.SNAPSHOT_CORPUS(p_snapshot_name VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = 'medrag v2 eval: record sha256 and PDF text layer of every corpus PDF under a new snapshot name'
EXECUTE AS OWNER
AS
$$
DECLARE
  v_existing INTEGER;
  v_files    INTEGER;
  v_pages    INTEGER;
  snapshot_exists EXCEPTION (-20201, 'SNAPSHOT_CORPUS: this snapshot name already exists; use a new name');
BEGIN
  SELECT COUNT(*) INTO :v_existing
    FROM EVAL.CORPUS_FILES
   WHERE snapshot_name = :p_snapshot_name;
  IF (v_existing > 0) THEN
    RAISE snapshot_exists;
  END IF;

  -- 每个文件只读一次,结果先放进临时表,再分别写两张表。
  CREATE OR REPLACE TEMPORARY TABLE EVAL.SNAPSHOT_PAGES AS
    SELECT d.relative_path, d.size, d.etag,
           p.sha256, p.page_number, p.page_count, p.page_text
      FROM DIRECTORY(@INGEST.CORPUS_STAGE) d,
           TABLE(EVAL.PDF_PAGES_OF(
             BUILD_SCOPED_FILE_URL(@INGEST.CORPUS_STAGE, d.relative_path)
           )) p
     WHERE d.relative_path ILIKE '%.pdf';

  -- 同一个文件(sha256)以前抽过就不再写。
  INSERT INTO EVAL.PDF_PAGES (sha256, page_number, page_text, extractor)
    SELECT DISTINCT s.sha256, s.page_number, s.page_text, 'pypdf 6.8.0'
      FROM EVAL.SNAPSHOT_PAGES s
     WHERE NOT EXISTS (SELECT 1 FROM EVAL.PDF_PAGES p WHERE p.sha256 = s.sha256);
  v_pages := SQLROWCOUNT;

  INSERT INTO EVAL.CORPUS_FILES (
    snapshot_name, doc_id, relative_path, sha256, size, etag, page_count
  )
    SELECT :p_snapshot_name, REPLACE(relative_path, '.pdf', ''), relative_path,
           ANY_VALUE(sha256), ANY_VALUE(size), ANY_VALUE(etag), MAX(page_count)
      FROM EVAL.SNAPSHOT_PAGES
     GROUP BY relative_path;
  v_files := SQLROWCOUNT;

  DROP TABLE IF EXISTS EVAL.SNAPSHOT_PAGES;
  RETURN v_files::VARCHAR || ' files, ' || v_pages::VARCHAR || ' new pages';
END;
$$;

-- call EVAL.SNAPSHOT_CORPUS('corpus_2026_10_03');
-- select snapshot_name, count(*), sum(page_count) from EVAL.CORPUS_FILES group by 1;
-- select count_if(nullif(trim(page_text), '') is null) empty_pages, count(*) from EVAL.PDF_PAGES;
