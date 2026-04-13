############################
# Global / Azure
############################

variable "location" {
  description = "Azure deployment region"
  type        = string
  default     = "westeurope"
}

############################
# HCP / Vault
############################

variable "vault_hcp_project_id" {
  description = "HCP project ID to deploy the HCP Vault cluster to"
  type        = string
}

############################
# AAP / EDA
############################

variable "aap_host" {
  description = "Base URL/endpoint of AAP (Developer Portal instance)"
  type        = string
}

############################
# EDA Project (Git)
############################

variable "eda_project_scm_url" {
  description = "Git URL for EDA rulebooks repo"
  type        = string
  default     = ""
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
