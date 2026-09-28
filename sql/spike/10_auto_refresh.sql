-- 环节 1:自动刷新实验。只在容器的 spike/ 下做,不进部署入口,在 Snowsight 的 worksheet 里一段一段手动执行。
-- 说明和验收见 docs/hands-on.md 环节 1。实验对象几乎不花钱:没有 task,不调 AI 函数。
-- 做完告诉 agent;删 SPIKE_STAGE、SPIKE_STREAM 和 spike/ 下的文件之前会先问你。
--
-- 准备:本机两份不同的小 PDF,下面叫 <PDF_1>、<PDF_2>,随便什么内容都行。
-- Azure 这边的命令在仓库根目录执行,存储账户名从 terraform output 取,不写进任何文件:
--   ACCT=$(terraform -chdir=infra/azure output -raw stage_base_url | sed -E 's#^azure://([^.]+)\..*#\1#')
--   上传或覆盖:az storage blob upload --auth-mode key --account-name "$ACCT" --container-name corpus \
--                 --name spike/<文件名> --file <本地文件> --overwrite
--   删除:      az storage blob delete --auth-mode key --account-name "$ACCT" --container-name corpus --name spike/<文件名>
--   看队列:    az storage message peek --auth-mode key --account-name "$ACCT" --queue-name medrag-events --num-messages 32
--              (peek 只看不取,不影响 Snowflake。消息内容是 base64,解码后是 Event Grid 事件的 JSON。)


-- =====================================================================
-- 第 0 步(Azure):还没有任何 stage 时,先上传 spike/a.pdf(用 <PDF_1>)。
--   然后 peek 队列,找到这条消息,看它的 eventType、data.api、subject。
-- =====================================================================


-- =====================================================================
-- 第 1 步(Snowflake):建 SPIKE_STAGE 和 SPIKE_STREAM。
--   这里故意用默认的 REFRESH_ON_CREATE(TRUE),和 sql/04_stage.sql 的做法相反,看看会怎样。
--   stage 地址从存储集成读出来再拼上 spike/,不用粘贴账户值。
-- =====================================================================
USE ROLE MEDRAG_ADMIN;
USE SCHEMA MEDRAG.INGEST;

EXECUTE IMMEDIATE $$
DECLARE
  v_base VARCHAR;
  v_stmt VARCHAR;
BEGIN
  DESC STORAGE INTEGRATION MEDRAG_AZURE_STORAGE_INT;
  SELECT "property_value" INTO :v_base
    FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
   WHERE "property" = 'STORAGE_ALLOWED_LOCATIONS';
  v_stmt := 'CREATE STAGE IF NOT EXISTS MEDRAG.INGEST.SPIKE_STAGE'
         || ' URL = ''' || v_base || 'spike/'''
         || ' STORAGE_INTEGRATION = MEDRAG_AZURE_STORAGE_INT'
         || ' DIRECTORY = (ENABLE = TRUE AUTO_REFRESH = TRUE NOTIFICATION_INTEGRATION = ''MEDRAG_AZURE_QUEUE_INT'')'
         || ' COMMENT = ''medrag v2: auto-refresh experiment on spike/; drop after the experiment''';
  EXECUTE IMMEDIATE :v_stmt;
  RETURN 'SPIKE_STAGE ready';
END;
$$;

CREATE STREAM IF NOT EXISTS SPIKE_STREAM
  ON STAGE SPIKE_STAGE
  COMMENT = 'medrag v2: auto-refresh experiment; drop after the experiment';

-- ===== 你来写:查询 Q1 directory table 里有哪些文件 =====
-- 提示:directory table 用 DIRECTORY(@<stage>) 这个表函数查;看 RELATIVE_PATH、ETAG、LAST_MODIFIED 几列。
-- 每一步之后都跑一次。
-- ===== 到这里 =====

-- ===== 你来写:查询 Q2 stream 里有什么 =====
-- 提示:stream 可以像表一样 SELECT;除了文件的列,还要看 METADATA$ACTION、METADATA$ISUPDATE。
-- 每一步之后都跑一次。
-- ===== 到这里 =====

-- 问题 1:a.pdf 在 directory table 里吗?在 stream 里吗?为什么?
--         (提示:stream 从哪一刻开始记变化;sql/04_stage.sql 的文件头。)
-- 再 peek 一次队列:第 0 步那条消息还在吗?


-- =====================================================================
-- 第 2 步(Azure):上传 spike/b.pdf(用 <PDF_2>)。等一两分钟,再跑 Q1、Q2。
-- =====================================================================
-- 问题 2:b.pdf 出现在哪里?从上传到出现在 stream 里大概多久?
--         (想精确看,可以找找官方的 AUTO_REFRESH_REGISTRATION_HISTORY 表函数。)


-- =====================================================================
-- 第 3 步(Azure):用 <PDF_2> 覆盖 spike/a.pdf(同一个名字,带 --overwrite)。等一两分钟,再跑 Q1、Q2。
-- =====================================================================
-- 问题 3:覆盖在 stream 里是几行?每行的 ETAG、METADATA$ACTION、METADATA$ISUPDATE 各是什么?
--         这就是先验证第 2 项要记的"覆盖在 stream 里是什么样子",写进 docs/decisions.md。


-- =====================================================================
-- 第 4 步(Snowflake):消费 stream。
-- =====================================================================
-- ===== 你来写:消费 SPIKE_STREAM =====
-- 要做什么:先只 SELECT 一次 SPIKE_STREAM,再跑 Q2,看它还在不在;
--           然后用一条 DML 把 stream 里的行写进你自己建的临时表(TEMPORARY TABLE),再跑 Q2。
-- 提示:哪些语句会让 stream 前进,见官方 Introduction to streams 里 "offset" 的部分。
--       这条 DML 就是环节 2A 的练习:以后写进的是 FILE_STATE,不是临时表。
-- ===== 到这里 =====
-- 问题 4:只 SELECT 之后 stream 还有数据吗?消费之后呢?临时表里是几行?


-- =====================================================================
-- 第 5 步(Azure):删除 spike/b.pdf。等一两分钟,再跑 Q1、Q2。
-- =====================================================================
-- 问题 5:b.pdf 在 stream 里是什么样?


-- =====================================================================
-- 第 6 步(可选,Azure):上传 spike/c.pdf,不查 stream,马上删掉它。等一两分钟,再跑 Q2。
-- =====================================================================
-- 问题 6:c.pdf 在 stream 里吗?为什么?(提示:stream 返回的是两个时间点之间的净变化。)
