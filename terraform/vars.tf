############################
# Global
############################

variable "location" {
  description = "Azure deployment region"
  type        = string
  default     = "westeurope"
}

############################
# Azure
############################

variable "azure_container_app_image" {
  description = "Container image for Azure Container App (WS client + SB sender)"
  type        = string
  default     = "ghcr.io/lakrass/vault-eda-demo-relay:latest"
}

############################
# HCP Vault
############################

variable "vault_hcp_project_id" {
  description = "HCP project ID to deploy the HCP Vault cluster to"
  type        = string
}

############################
# AAP
############################

variable "aap_host" {
  description = "Base URL/endpoint of AAP (Developer Portal instance)"
  type        = string
}

############################
# EDA
############################

variable "eda_project_scm_url" {
  description = "Git URL for EDA rulebooks repo"
  type        = string
  default     = "https://github.com/lakrass/vault-eda-demo"
}

variable "eda_decision_environment" {
  description = "Git URL for EDA rulebooks repo"
  type        = string
  default     = "ghcr.io/lakrass/vault-eda-demo-de:latest"
}

############################
# Helper
############################

resource "random_string" "suffix" {
  length  = 5
  upper   = false
  numeric = true
  special = false
}
