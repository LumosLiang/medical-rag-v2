--!jinja
-- 账户级引导对象:Azure 存储集成和通知集成,以及把它们的 USAGE 授给 MEDRAG_ADMIN。
-- 可以重复执行:已经存在的集成不会被改动。必须在 00_role.sql 之后执行。
--
-- 用 ACCOUNTADMIN 执行。三个值取自 infra/azure 的 terraform output,执行时传入,不写进仓库:
--   snow sql -f sql/01_integrations.sql --enable-templating JINJA \
--     -D tenant_id="$(terraform -chdir=infra/azure output -raw tenant_id)" \
--     -D stage_base_url="$(terraform -chdir=infra/azure output -raw stage_base_url)" \
--     -D queue_url="$(terraform -chdir=infra/azure output -raw queue_url)"
--
-- 执行完:两条 DESC 结果里各有一个 AZURE_CONSENT_URL,在浏览器里各打开一次、点 Accept。
-- 两个 service principal 在 Azure 租户里出现后(可能要一小时以上),再做 infra/azure 的第二阶段。
--
-- 官方文档里的注意事项(见 docs/pitfalls.md):
--   - 不要对这两个集成 CREATE OR REPLACE,会让引用它们的 stage 失效;要改就用 ALTER。
--   - 存储集成和通知集成在 Azure 里是两个不同的 service principal。
--   - 一个队列只能给一个通知集成。

USE ROLE ACCOUNTADMIN;

-- 放行整个 corpus 容器:pdf/(语料)、manifest/(语料清单)、spike/(先验证)都在里面。
-- Azure 那边只给这个集成 Storage Blob Data Reader,Snowflake 只能读。
CREATE STORAGE INTEGRATION IF NOT EXISTS MEDRAG_AZURE_STORAGE_INT
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'AZURE'
  ENABLED = TRUE
  AZURE_TENANT_ID = '{{ tenant_id }}'
  STORAGE_ALLOWED_LOCATIONS = ('{{ stage_base_url }}')
  COMMENT = 'medrag v2: read-only access to the Azure corpus container';

-- directory table 自动刷新用。队列只给这一个集成读。
CREATE NOTIFICATION INTEGRATION IF NOT EXISTS MEDRAG_AZURE_QUEUE_INT
  ENABLED = TRUE
  TYPE = QUEUE
  NOTIFICATION_PROVIDER = AZURE_STORAGE_QUEUE
  AZURE_STORAGE_QUEUE_PRIMARY_URI = '{{ queue_url }}'
  AZURE_TENANT_ID = '{{ tenant_id }}'
  COMMENT = 'medrag v2: Event Grid messages for directory table auto-refresh';

-- MEDRAG_ADMIN 建 stage 时要用这两个集成:stage 引用存储集成,directory table 的自动刷新引用通知集成。
GRANT USAGE ON INTEGRATION MEDRAG_AZURE_STORAGE_INT TO ROLE MEDRAG_ADMIN;
GRANT USAGE ON INTEGRATION MEDRAG_AZURE_QUEUE_INT TO ROLE MEDRAG_ADMIN;

-- consent 要用的 AZURE_CONSENT_URL 和 AZURE_MULTI_TENANT_APP_NAME 在这两条的结果里。
DESC STORAGE INTEGRATION MEDRAG_AZURE_STORAGE_INT;
DESC NOTIFICATION INTEGRATION MEDRAG_AZURE_QUEUE_INT;
