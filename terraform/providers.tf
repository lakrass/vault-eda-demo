provider "hcp" {
  project_id = var.vault_hcp_project_id
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "aap" {
  endpoint = var.aap_host
}

provider "vault" {
  address   = hcp_vault_cluster.vault.vault_public_endpoint_url
  token     = hcp_vault_cluster_admin_token.token.token
  namespace = hcp_vault_cluster.vault.namespace
}
