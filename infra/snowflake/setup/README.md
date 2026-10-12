# Snowflake 初始化

这里集中管理项目运行所需的资源及授权，独立于日常 SQL 发布和应用升级。

| 文件 | 初始化对象 | 执行角色 |
|---|---|---|
| `00_role_and_database.sql` | 项目角色、数据库、warehouse 使用权限与 Cortex 权限 | ACCOUNTADMIN |
| `01_azure_integrations.sql` | Azure storage / notification integrations | ACCOUNTADMIN |
| `02_schemas.sql` | INGEST、CORE、EVAL、OPS | MEDRAG_ADMIN |
| `03_git_repository.sql` | Git API integration 与 repository | 按文件切换角色 |
| `04_spcs.sql` | 计算池、镜像仓库、spec stage 与端点权限 | 按文件切换角色 |

Azure 集成的 tenant、stage 和 queue 地址来自 Terraform 输出；Git repository 地址执行时传入。私有仓库 secret 由用户在 Snowflake 中创建，内容不经过仓库。完成 Azure consent 后，再授予两个 service principal 对应的文件及队列权限。

角色与库先于集成和 schema，schema 与 Git secret 先于 repository；SPCS 资源在首次容器发布前准备。当前账户已完成初始化，不因目录整理重新执行授权或转移所有权。日常发布流程见 [部署说明](../../../docs/deployment.md)。
