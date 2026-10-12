"""在 SQLite 执行指标的基础查询，验证分母和完成状态；不替代 Snowflake 部署验收。"""
from pathlib import Path
import sqlite3


def per_question():
    connection = sqlite3.connect(':memory:')
    connection.create_function('IFF', 3, lambda condition, yes, no: yes if condition else no)
    connection.execute("ATTACH DATABASE ':memory:' AS EVAL")
    connection.executescript('''
      CREATE TABLE EVAL.EXPERIMENTS (experiment_id TEXT, set_name TEXT, finished_at TEXT);
      CREATE TABLE EVAL.QUESTION_SETS (set_name TEXT, question_id TEXT);
      CREATE TABLE EVAL.QUESTIONS (question_id TEXT, question_type TEXT);
      CREATE TABLE EVAL.RETRIEVAL_RESULTS (
        experiment_id TEXT, question_id TEXT, rank INTEGER,
        hit_doc BOOLEAN, hit_evidence BOOLEAN, latency_ms INTEGER
      );
      INSERT INTO EVAL.QUESTION_SETS VALUES ('fixed', 'answered'), ('fixed', 'zero_results');
      INSERT INTO EVAL.QUESTIONS VALUES ('answered', 'fact'), ('zero_results', 'fact');
      INSERT INTO EVAL.EXPERIMENTS VALUES
        ('complete', 'fixed', '2026-10-06'), ('unfinished', 'fixed', NULL);
      INSERT INTO EVAL.RETRIEVAL_RESULTS VALUES
        ('complete', 'answered', 1, TRUE, TRUE, 20),
        ('unfinished', 'answered', 1, TRUE, TRUE, 20);
    ''')
    sql = (Path(__file__).resolve().parents[2] / 'eval/retrieval/metrics.sql').read_text()
    # 执行文件里的实际 per_question CTE；GROUPING SETS 是 Snowflake 部分，留给运行验收。
    query = sql[sql.index('WITH per_question AS ('):sql.index('scored AS (')].rstrip().rstrip(',')
    rows = connection.execute(query + ' SELECT * FROM per_question').fetchall()
    connection.close()
    return rows


def test_zero_results_remain_in_the_metric_denominator():
    rows = per_question()
    assert len(rows) == 2
    zero = next(row for row in rows if row[1] == 'zero_results')
    assert zero[3:5] == (None, None)
    assert sum(row[4] == 1 for row in rows) / len(rows) == 0.5


def test_unfinished_experiment_is_excluded_from_final_metrics():
    assert {row[0] for row in per_question()} == {'complete'}
