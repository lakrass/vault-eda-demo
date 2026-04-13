############################
# HCP Vault Instance
############################

resource "hcp_hvn" "hvn" {
  hvn_id         = "vault-eda-demo"
  cloud_provider = "azure"
  region         = var.location
}

resource "hcp_vault_cluster" "vault" {
  cluster_id      = "vault-eda-demo"
  hvn_id          = hcp_hvn.hvn.hvn_id
  tier            = "dev"
  public_endpoint = true
}

resource "hcp_vault_cluster_admin_token" "token" {
  cluster_id = hcp_vault_cluster.vault.cluster_id
}

############################
# Outputs
############################

output "vault_url" {
  value = hcp_vault_cluster.vault.vault_public_endpoint_url
}

output "vault_admin_token" {
  value       = hcp_vault_cluster_admin_token.token.token
  sensitive   = true
  description = "Vault admin token for cluster initialization"
}
