variable "location" {
  description = "Azure 区域。和 Snowflake 账户同在东京。"
  type        = string
  default     = "japaneast"
}

variable "resource_group_name" {
  type    = string
  default = "medrag-rg"
}

variable "storage_account_name" {
  description = "存储账户名,全局唯一。真实值写在 terraform.tfvars,不进仓库。"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name 只能是 3 到 24 位小写字母和数字。"
  }
}

variable "container_name" {
  type    = string
  default = "corpus"
}

variable "queue_name" {
  type    = string
  default = "medrag-events"
}

# 下面两个在 Snowflake 两个集成完成 consent、service principal 出现之后才有值。
# 为 null 时不建第二阶段的资源(角色分配、事件订阅)。

variable "snowflake_storage_sp_object_id" {
  description = "Snowflake 存储集成在本租户里的 service principal 对象 ID。"
  type        = string
  default     = null
}

variable "snowflake_queue_sp_object_id" {
  description = "Snowflake 通知集成在本租户里的 service principal 对象 ID。"
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = { project = "medrag" }
}
