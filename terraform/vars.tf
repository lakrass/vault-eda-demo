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
  default     = "ghcr.io/lakrass/vault-eda-demo-relay:main"
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

variable "aap_execution_environment" {
  description = "Git URL for EDA rulebooks repo"
  type        = string
  default     = "ghcr.io/lakrass/vault-eda-demo-ee:main"
}

############################
# EDA
############################

variable "eda_decision_environment" {
  description = "Git URL for EDA rulebooks repo"
  type        = string
  default     = "ghcr.io/lakrass/vault-eda-demo-de:main"
}

variable "eda_playbook_path" {
  description = "Path to the EDA playbook"
  type        = string
  default     = "playbooks/deploy-secret.yaml"
}

############################
# Helper
############################

resource "random_string" "eda_password" {
  length  = 30
  upper   = true
  numeric = true
  special = true
}
