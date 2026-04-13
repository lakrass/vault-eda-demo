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

output "vault_url" {
  value = hcp_vault_cluster.vault.vault_public_endpoint_url
}
