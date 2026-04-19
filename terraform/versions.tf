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

    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.8"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.8"
    }

    http = {
      source  = "hashicorp/http"
      version = "~> 3.5"
    }
  }
}
