-- 出草稿题:按固定种子抽文档,每篇用 AI_COMPLETE 读 PDF 文字层出一题,写进 EVAL.QUESTIONS,状态 DRAFT。
-- 用法:CALL MEDRAG.EVAL.DRAFT_QUESTIONS('<snapshot_name>', <题数>, <种子>);返回这次写入的题数。
--   这个快照里已经有任何状态的题的文档都跳过:同一个种子调大题数,只给新抽到的文档出题,
--   不会重出、也不会替换已有的题。改题和换掉被拒的题走审核导入(review_questions.sql),不靠重跑。
--   串行调用;两个会话同时调可能出重复题(标准表的 PRIMARY KEY 不强制唯一)。
--
-- 草稿只是起点:审核时打开 PDF 核对页码、证据和答案,通过的设 APPROVED。
-- evidence_in_pdf 只说明证据能在那一页的文字层里定位到,不说明答案对、也不说明证据回答了问题。
-- 文字层可能有字形问题(比如 = 被抽成 ¼、− 被抽成 /C0),证据以 PDF 上看到的为准。

USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

CREATE OR REPLACE PROCEDURE EVAL.DRAFT_QUESTIONS(
  p_snapshot_name VARCHAR,
  p_n_docs        NUMBER,
  p_seed          NUMBER
)
RETURNS NUMBER
LANGUAGE SQL
COMMENT = 'medrag v2 eval: draft one question per sampled document with AI_COMPLETE from the PDF text layer'
EXECUTE AS OWNER
AS
$$
DECLARE
  -- 模型与 prompt 版本随草稿保存，便于区分生成依据。
  v_model          VARCHAR DEFAULT 'claude-sonnet-4-5';
  v_prompt_version VARCHAR DEFAULT 'draft_v2';
  v_batch_id       VARCHAR DEFAULT UUID_STRING();
  v_inserted       INTEGER;
BEGIN
  -- 1. 抽文档:按 (种子, doc_id) 的哈希排序取前 p_n_docs 篇;排名决定题型,五种轮流。
  --    已经有题的文档也占名额,这样同一个种子调大题数时,前面抽到的文档不变。
  CREATE OR REPLACE TEMPORARY TABLE EVAL.DRAFT_DOCS AS
    SELECT f.doc_id, f.sha256, f.page_count,
           DECODE(MOD(f.rk, 5),
                  0, 'fact', 1, 'number', 2, 'conclusion', 3, 'method', 4, 'table') AS question_type
      FROM (SELECT doc_id, sha256, page_count,
                   ROW_NUMBER() OVER (ORDER BY HASH(:p_seed, doc_id)) - 1 AS rk
              FROM EVAL.CORPUS_FILES
             WHERE snapshot_name = :p_snapshot_name) f
     WHERE f.rk < :p_n_docs
       AND NOT EXISTS (SELECT 1 FROM EVAL.QUESTIONS q
                        WHERE q.snapshot_name = :p_snapshot_name AND q.doc_id = f.doc_id);

  -- 2. 每篇调一次模型。结果先落进临时表:放在 CTE 里会被重复调用、重复计费。
  CREATE OR REPLACE TEMPORARY TABLE EVAL.DRAFT_RAW AS
    SELECT d.doc_id, d.sha256, d.page_count, d.question_type,
           AI_COMPLETE(
             model => :v_model,
             prompt => 'You are writing one evaluation question for a retrieval system over about 200 medical research articles. '
               || 'Read the article below. Its text is split into pages marked [[PAGE n]].\n\n'
               || 'Write exactly one question of type "' || d.question_type || '" '
               || '(fact = a specific finding or detail; number = a specific numeric result; conclusion = the authors'' main conclusion; '
               || 'method = how the study was done, e.g. design, population, intervention, measurement; '
               || 'table = a value that can only be read from a table, not from the running text).\n'
               || 'Rules:\n'
               || '- The question must be answerable from one page, and the answer must be stated there; never write a question the page does not answer.\n'
               || '- The question must stand on its own: name the condition, population, intervention and, for comparisons, the reference group, '
               || 'so a reader can tell which study and which result it is about; do not quote the title.\n'
               || '- Use your own wording; do not copy more than four consecutive words from the passage.\n'
               || '- Do not use the reference list, author affiliations, funding, acknowledgements or journal front matter.\n'
               || '- reference_answer is one short sentence. Every fact in it must be in the evidence; add nothing else.\n'
               || '- evidence_text is copied character for character from that page, 1 to 2 sentences, at most 400 characters.\n'
               || '- evidence_parts lists every verbatim fragment needed to support the answer. For a table question, include the table caption, '
               || 'the column header(s) and the row label(s) as separate fragments, plus the cell value(s), so the value can be attributed without the table. '
               || 'For other questions, evidence_parts holds only evidence_text.\n'
               || '- tags: zero or more of table, numeric, abbreviation, section_specific, paraphrased.\n\n'
               || 'Article:\n' || pages.article_text,
             model_parameters => {'temperature': 0},
             response_format => {
               'type': 'json',
               'schema': {
                 'type': 'object',
                 'properties': {
                   'question':         {'type': 'string'},
                   'reference_answer': {'type': 'string'},
                   'page_number':      {'type': 'integer'},
                   'evidence_text':    {'type': 'string'},
                   'evidence_parts':   {'type': 'array', 'items': {'type': 'string'}},
                   'tags':             {'type': 'array', 'items': {'type': 'string'}}
                 },
                 'required': ['question', 'reference_answer', 'page_number', 'evidence_text', 'evidence_parts', 'tags']
               }
             }
           ) AS draft
      FROM EVAL.DRAFT_DOCS d,
           LATERAL (SELECT LISTAGG('[[PAGE ' || p.page_number || ']]\n' || COALESCE(p.page_text, ''), '\n\n')
                             WITHIN GROUP (ORDER BY p.page_number) AS article_text
                      FROM EVAL.PDF_PAGES p
                     WHERE p.sha256 = d.sha256) pages;

  -- 3. 写进题库。问题、答案、证据不能为空,页码要在 1 到页数之间;不合格的草稿直接丢掉。
  --    evidence_in_pdf:证据(以及每个 evidence_parts 片段)都能在那一页的文字层里定位到。
  INSERT INTO EVAL.QUESTIONS (
    question_id, snapshot_name, doc_id, sha256, page_number, question, reference_answer,
    evidence_text, evidence_parts, question_type, tags, evidence_in_pdf, status, source,
    draft_model, prompt_version, seed, draft_batch_id)
  SELECT 'q_' || LEFT(SHA2(:p_snapshot_name || '|' || r.doc_id || '|'
                           || r.draft:question::VARCHAR, 256), 16),
         :p_snapshot_name, r.doc_id, r.sha256,
         r.draft:page_number::NUMBER,
         r.draft:question::VARCHAR,
         r.draft:reference_answer::VARCHAR,
         r.draft:evidence_text::VARCHAR,
         r.draft:evidence_parts::ARRAY,
         r.question_type,
         r.draft:tags::ARRAY,
         EVAL.EVIDENCE_LOCATED(p.page_text, r.draft:evidence_text::VARCHAR,
                               r.draft:evidence_parts::ARRAY),
         'DRAFT', 'AI_DRAFT', :v_model, :v_prompt_version, :p_seed, :v_batch_id
    FROM EVAL.DRAFT_RAW r
    LEFT JOIN EVAL.PDF_PAGES p
      ON p.sha256 = r.sha256 AND p.page_number = r.draft:page_number::NUMBER
   WHERE NULLIF(TRIM(r.draft:question::VARCHAR), '') IS NOT NULL
     AND NULLIF(TRIM(r.draft:reference_answer::VARCHAR), '') IS NOT NULL
     AND NULLIF(EVAL.NORMALIZE_TEXT(r.draft:evidence_text::VARCHAR), '') IS NOT NULL
     AND r.draft:page_number::NUMBER BETWEEN 1 AND r.page_count;
  v_inserted := SQLROWCOUNT;

  -- 4. 模型常把页码标错一页。只处理这一批新写的题:证据恰好只在另一页定位到时改成那一页,
  --    备注追加原页码。改了页码也只是 DRAFT,证据是否回答问题仍要审核。
  UPDATE EVAL.QUESTIONS q
     SET page_number     = f.found_page,
         evidence_in_pdf = TRUE,
         reviewer_note   = COALESCE(q.reviewer_note || '; ', '')
                           || 'page corrected from ' || q.page_number::VARCHAR || ' by text-layer match'
    FROM (SELECT q2.question_id, MIN(p.page_number) AS found_page
            FROM EVAL.QUESTIONS q2
            JOIN EVAL.PDF_PAGES p
              ON p.sha256 = q2.sha256
             AND EVAL.EVIDENCE_LOCATED(p.page_text, q2.evidence_text, q2.evidence_parts)
           WHERE q2.draft_batch_id = :v_batch_id
             AND NOT COALESCE(q2.evidence_in_pdf, FALSE)
           GROUP BY q2.question_id
          HAVING COUNT(*) = 1) f
   WHERE q.question_id = f.question_id;

  DROP TABLE IF EXISTS EVAL.DRAFT_DOCS;
  DROP TABLE IF EXISTS EVAL.DRAFT_RAW;
  RETURN v_inserted;
END;
$$;

-- call EVAL.DRAFT_QUESTIONS('corpus_2026_10_03', 50, 20261003);
-- select question_type, count(*), count_if(evidence_in_pdf) from EVAL.QUESTIONS group by 1;
