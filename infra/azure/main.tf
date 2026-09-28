# 第一阶段:资源组、存储账户(ADLS Gen2)、容器、事件队列、Event Grid system topic。
# 第二阶段:Snowflake 两个集成 consent 之后,在 terraform.tfvars 里填上两个
# service principal 的对象 ID 再 apply,才会建角色分配和事件订阅。

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# StorageV2 + 分层命名空间,即 ADLS Gen2。只放本项目的语料。
resource "azurerm_storage_account" "corpus" {
  name                            = var.storage_account_name
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  is_hns_enabled                  = true
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  tags                            = var.tags
}

resource "azurerm_storage_container" "corpus" {
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.corpus.id
  container_access_type = "private"
}

# 只给 Snowflake 通知集成一个消费者。
resource "azurerm_storage_queue" "events" {
  name               = var.queue_name
  storage_account_id = azurerm_storage_account.corpus.id
}

resource "azurerm_eventgrid_system_topic" "corpus" {
  name                = "medrag-corpus-events"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  source_resource_id  = azurerm_storage_account.corpus.id
  topic_type          = "Microsoft.Storage.StorageAccounts"
  tags                = var.tags
}

# Snowflake 只读 PDF,不写、不删。
resource "azurerm_role_assignment" "snowflake_blob_reader" {
  count = var.snowflake_storage_sp_object_id == null ? 0 : 1

  scope                = azurerm_storage_account.corpus.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = var.snowflake_storage_sp_object_id
  principal_type       = "ServicePrincipal"
}

# 官方写的最小角色。
resource "azurerm_role_assignment" "snowflake_queue_processor" {
  count = var.snowflake_queue_sp_object_id == null ? 0 : 1

  scope                = azurerm_storage_queue.events.id
  role_definition_name = "Storage Queue Data Message Processor"
  principal_id         = var.snowflake_queue_sp_object_id
  principal_type       = "ServicePrincipal"
}

# 只投递 directory table 自动刷新会处理的两类事件,再按官方给的 data.api 清单过滤:
# ADLS 上建空文件的 CreateFile 不算,只有 FlushWithClose(内容提交)才算。
# 事件格式保持 Event Grid schema,Snowflake 不支持 CloudEvents。
# 等队列权限就绪之后再建,避免往队列里堆 Snowflake 读不了的消息。
resource "azurerm_eventgrid_system_topic_event_subscription" "to_snowflake" {
  count = var.snowflake_queue_sp_object_id == null ? 0 : 1

  name                  = "medrag-to-snowflake"
  system_topic          = azurerm_eventgrid_system_topic.corpus.name
  resource_group_name   = azurerm_resource_group.this.name
  event_delivery_schema = "EventGridSchema"
  included_event_types  = ["Microsoft.Storage.BlobCreated", "Microsoft.Storage.BlobDeleted"]

  storage_queue_endpoint {
    storage_account_id = azurerm_storage_account.corpus.id
    queue_name         = azurerm_storage_queue.events.name
  }

  subject_filter {
    subject_begins_with = "/blobServices/default/containers/${var.container_name}/blobs/"
  }

  advanced_filter {
    string_in {
      key = "data.api"
      values = [
        "CopyBlob", "PutBlob", "PutBlockList", "FlushWithClose", "SftpCommit",
        "DeleteBlob", "DeleteFile", "SftpRemove",
      ]
    }
  }

  depends_on = [azurerm_role_assignment.snowflake_queue_processor]
}
