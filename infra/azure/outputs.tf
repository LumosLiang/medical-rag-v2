data "azurerm_client_config" "current" {}

output "tenant_id" {
  description = "Snowflake 两个集成的 AZURE_TENANT_ID。"
  value       = data.azurerm_client_config.current.tenant_id
}

output "stage_base_url" {
  description = "存储集成 STORAGE_ALLOWED_LOCATIONS 和 stage URL 的前缀。Snowflake 要求用 blob 端点,ADLS Gen2 也一样。"
  value       = "azure://${azurerm_storage_account.corpus.name}.blob.core.windows.net/${azurerm_storage_container.corpus.name}/"
}

output "queue_url" {
  description = "通知集成的 AZURE_STORAGE_QUEUE_PRIMARY_URI。"
  value       = azurerm_storage_queue.events.url
}

output "event_subscription_created" {
  description = "第二阶段的事件订阅是否已建。"
  value       = length(azurerm_eventgrid_system_topic_event_subscription.to_snowflake) == 1
}
