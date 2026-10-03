# 当前状态

2026-10-03 更新。代码部署与运行验收分开记录。

| 部分 | 状态 |
|---|---|
| Azure ADLS Gen2 → Event Grid → Queue → directory table | 已建立；此前实测新增、覆盖、删除可自动刷新 |
| Snowflake 入库 SQL | Git 提交 `4b39ec3` 已部署，`OPS.DEPLOY_LOG` 为 `SUCCEEDED` |
| CAPTURE_CHANGES、CLASSIFY_CHANGES、REMOVE_OLD_CHUNKS、RUN_INGEST | 2026-10-02 自动触发验收通过(见 INGEST_TASK 行):FILE_CHANGES 共 209 条 DONE、1 条 FAILED(`PMC9883575.pdf`,旧版切分留下的) |
| PARSE_FILE | 已验收：真实 etag 的 PDF 解析出 12 页，重复调用返回 SKIPPED；失败文件也已成功解析 12 页 |
| CHUNK_DOC | 新版已部署。9 份已完成文档补齐 700 个基线块：ID 唯一，无空块、NULL token 或过期版本；17 块超过 512 token，符合基线设计。同一文件重复切分两次均为 69 块且 ID 稳定。补切配置在一份文档上生成 69 块，均不超过 512 token。`PMC9883575.pdf` 仍为 FAILED，未补入基线 |
| INGEST_TASK | 2026-10-02 已 RESUME,现为 started。正式语料分 10 批上传(每批 20 篇,上一批处理完再传下一批),全程没有手动刷新或执行:上传后约 1 分钟 directory table 和 stream 自动更新,task 随即触发。共成功运行 11 次,每次 338–1825 秒,都在默认 60 分钟时限内;新增 200 篇没有失败 |
| Cortex Search | 基线服务 `MEDICAL_CHUNKS_RECURSIVE_ONCE_1200_200` 索引 13616 行,与 CHUNKS 基线配置(209 篇)一致。上传期间按 TARGET_LAG 自动增量刷新 6 次,都成功;新上传的文档能检索到。补切配置的 69 块未进入该服务 |
| 回答生成 | 本地已准备 AI_COMPLETE 与引用处理；/ask 留给用户填写，尚未做真实模型验收 |
| 项目结构 | Python 应用位于 `src/medical_rag/`，SQL 位于 `src/sql/`；初始化、Docker/SPCS、配置和验收分别归入 infra、deploy、config、tests。依赖统一到 pyproject.toml，部署入口与文档路径已对齐；包安装与导入、5 项单元测试、Streamlit 启动与未实现提示、本机镜像重建和容器连通检查通过；此次未重新部署 Snowflake |
| 前后端 | FastAPI / Streamlit 骨架已准备；Cortex Search 调用、API 路由、前端 HTTP 请求和 session_state 留给用户填写。5 项参数与引用处理测试、Streamlit 页面启动检查通过；完整链路尚未实现 |
| Docker / SPCS | 本机两个容器已启动，探针和页面返回 200，前端容器可请求后端 /search（未填写，返回 501）。Docker Hub 镜像元数据拉取停滞，本次使用本机缓存的官方 Python 3.12 镜像构建。SPCS 文件已准备但未执行，setup 含账户权限变更 |
| 自动数据检查、评测 | 后续再做 |
| 正式语料 | 2026-10-02 在本机下载 200 篇 PDF 到 `data/corpus/`(另有已入库的样本 10 篇在 `data/sample/`),分 10 批、每批 20 篇,每批跑完本机检查脚本并人工看题目后才跑下一批;最终全量检查 0 失败。脚本和数据都只在本机(`.gitignore`)。已上传到容器 `pdf/`(共 210 篇),入库后 209 篇解析出的页数与本地记录逐篇一致,共 2420 页;基线块 13616 个,无重复 ID、空块或 NULL token,407 块超过 512 token(基线只观察) |

`recursive_once_1200_200` 是 active 配置；补切策略名为 `recursive_resplit_to_512_tokens_1200_200`。旧名 `recursive_1200_200` 和历史块保留。切分代码位于 `src/sql/ingest/chunk/`。本次没有更改 Azure 资源。CLI 当前使用受限 PAT 会话，验收时显式指定 `MEDRAG_ADMIN`，临时副本去掉 `USE ROLE`；仓库脚本保留标准角色声明。

## 下一步

下一步按 `.harness/context/implementation.md` 填写前端 → /search → Cortex Search 的链路，跑通后再接 /ask。之前 FAILED 的文件仍需单独重试；task 现在是启动状态。覆盖和删除走 task 的情况还没实测。
