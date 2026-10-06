-- 从已完成实验的冻结题集起算指标，零返回题也记为未命中，避免分母变小。
USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

CREATE OR REPLACE VIEW EVAL.RETRIEVAL_METRICS
COMMENT = 'medrag v2 eval: per experiment (and per question type) doc/evidence hit@k, MRR, ceiling and latency'
AS
WITH per_question AS (
  SELECT e.experiment_id, s.question_id, q.question_type,
         MIN(IFF(rr.hit_doc, rr.rank, NULL))      AS first_doc_rank,
         MIN(IFF(rr.hit_evidence, rr.rank, NULL)) AS first_evidence_rank,
         MAX(rr.latency_ms)                       AS latency_ms
    FROM EVAL.EXPERIMENTS e
    JOIN EVAL.QUESTION_SETS s ON s.set_name = e.set_name
    JOIN EVAL.QUESTIONS q ON q.question_id = s.question_id
    LEFT JOIN EVAL.RETRIEVAL_RESULTS rr
      ON rr.experiment_id = e.experiment_id
     AND rr.question_id = s.question_id
   WHERE e.finished_at IS NOT NULL
   GROUP BY e.experiment_id, s.question_id, q.question_type
),
scored AS (
  SELECT p.*, c.coverable
    FROM per_question p
    LEFT JOIN EVAL.COVERAGE_CEILING c
      ON c.experiment_id = p.experiment_id
     AND c.question_id = p.question_id
)
SELECT experiment_id,
       COALESCE(question_type, 'ALL')                                  AS question_type,
       COUNT(*)                                                        AS n_questions,
       ROUND(AVG(IFF(first_doc_rank <= 1, 1, 0)), 3)                   AS doc_hit_at_1,
       ROUND(AVG(IFF(first_doc_rank <= 5, 1, 0)), 3)                   AS doc_hit_at_5,
       ROUND(AVG(IFF(first_doc_rank IS NOT NULL, 1, 0)), 3)            AS doc_hit_at_k,
       ROUND(AVG(COALESCE(1 / first_doc_rank, 0)), 3)                  AS doc_mrr,
       ROUND(AVG(IFF(first_evidence_rank <= 1, 1, 0)), 3)              AS evidence_hit_at_1,
       ROUND(AVG(IFF(first_evidence_rank <= 5, 1, 0)), 3)              AS evidence_hit_at_5,
       ROUND(AVG(IFF(first_evidence_rank IS NOT NULL, 1, 0)), 3)       AS evidence_hit_at_k,
       ROUND(AVG(COALESCE(1 / first_evidence_rank, 0)), 3)             AS evidence_mrr,
       ROUND(AVG(IFF(coverable, 1, 0)), 3)                             AS coverable_rate,
       ROUND(MEDIAN(latency_ms))                                       AS latency_p50_ms
  FROM scored
 GROUP BY GROUPING SETS ((experiment_id), (experiment_id, question_type));
