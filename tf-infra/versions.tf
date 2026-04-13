terraform {
  required_version = ">= 1.5.0"

  required_providers {
    hcp = {
      source  = "hashicorp/hcp"
      version = "~> 0.111"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.68"
    }

    aap = {
      source  = "tfbrew/aap"
      version = "~> 2.2"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.8"
    }
  }
}

provider "hcp" {
  project_id = var.vault_hcp_project_id
}

provider "azurerm" {
  features {}
}

provider "aap" {
  endpoint = var.aap_host
}
