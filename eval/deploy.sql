-- 评测工具独立于应用部署；这里只建立对象，不生成题目、不启动实验。
USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;
USE WAREHOUSE MEDICAL_RAG_INDEX_WH;

EXECUTE IMMEDIATE FROM './schema.sql';
EXECUTE IMMEDIATE FROM './dataset/snapshot.sql';
EXECUTE IMMEDIATE FROM './dataset/draft_questions.sql';
EXECUTE IMMEDIATE FROM './dataset/review_questions.sql';
EXECUTE IMMEDIATE FROM './dataset/question_sets.sql';
EXECUTE IMMEDIATE FROM './retrieval/score_evidence.sql';
EXECUTE IMMEDIATE FROM './retrieval/run_experiment.sql';
EXECUTE IMMEDIATE FROM './retrieval/metrics.sql';
