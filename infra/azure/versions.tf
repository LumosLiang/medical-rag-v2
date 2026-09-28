terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.7"
    }
  }
}

# 订阅取 az CLI 当前的默认订阅(azurerm v5 支持),不写进仓库。
provider "azurerm" {
  features {}

  # v5 默认不注册任何资源提供程序,这里只列用到的两个。
  resource_provider_registrations = "none"
  resource_providers_to_register  = ["Microsoft.Storage", "Microsoft.EventGrid"]
}
