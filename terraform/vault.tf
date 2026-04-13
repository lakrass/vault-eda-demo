############################
# Key-Value Secret Engine
############################

resource "vault_mount" "kv" {
  path = "secret"
  type = "kv-v2"
}

resource "vault_kv_secret_v2" "demo_secret" {
  mount = vault_mount.kv.path
  name  = "demo-secret"

  data_json = jsonencode({
    demo_secret = "This is a secret retrieved from Vault using EDA!"
  })
}

############################
# Policies
############################

resource "vault_policy" "relay" {
  name = "vault-eda-relay"

  policy = <<-EOH
    # Allow subscription to event stream (WebSocket)
    path "sys/events/subscribe/*" {
      capabilities = ["read"]
    }

    # Allow receiving events for secrets under "secret/*"
    path "secret/*" {
      capabilities = ["list", "subscribe"]
      subscribe_event_types = ["*"]
    }
  EOH
}

resource "vault_policy" "demo_user" {
  name = "demo-user-kv"

  policy = <<-EOH
    # Allow UI visibility of the KV engine
    path "sys/internal/ui/mounts/secret" {
      capabilities = ["read"]
    }

    # Allow listing inside the KV engine
    path "secret/metadata/*" {
      capabilities = ["list"]
    }

    # Allow actual secret access
    path "secret/data/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }
  EOH
}

resource "vault_policy" "aap" {
  name = "aap"

  policy = <<-EOH
    # Allow secret read access
    path "secret/data/*" {
      capabilities = ["read"]
    }
  EOH
}

############################
# Azure Auth Method
############################

data "azurerm_client_config" "current" {}

resource "vault_auth_backend" "azure" {
  type        = "azure"
  description = "Azure authentication for managed identities"
}

resource "vault_azure_auth_backend_config" "azure_config" {
  backend   = vault_auth_backend.azure.path
  tenant_id = data.azurerm_client_config.current.tenant_id
  resource  = "https://management.azure.com"

}

resource "vault_azure_auth_backend_role" "vault_eda_relay" {
  backend = vault_auth_backend.azure.path
  role    = "vault-eda-relay"

  bound_service_principal_ids = [
    data.azurerm_client_config.current.object_id,
    azurerm_user_assigned_identity.umi.principal_id
  ]

  token_ttl      = 3600
  token_max_ttl  = 86400
  token_policies = [vault_policy.relay.name]
}

############################
# Userpass Auth Method
############################

resource "vault_auth_backend" "userpass" {
  type = "userpass"
}

resource "vault_generic_endpoint" "demo_user" {
  depends_on = [vault_auth_backend.userpass]
  path       = "auth/userpass/users/demo"

  data_json = jsonencode({
    password = "demo"
    policies = [vault_policy.demo_user.name]
  })
}

############################
# Approle Auth Method
############################
resource "vault_auth_backend" "approle" {
  type = "approle"
}

resource "vault_approle_auth_backend_role" "aap" {
  backend        = vault_auth_backend.approle.path
  role_name      = "aap"
  token_policies = [vault_policy.aap.name]
}

resource "vault_approle_auth_backend_role_secret_id" "aap" {
  backend   = vault_auth_backend.approle.path
  role_name = vault_approle_auth_backend_role.aap.role_name
}

############################
# Outputs
############################

output "vault_kv_path" {
  value       = vault_mount.kv.path
  description = "Path to the KV secret engine"
}

output "vault_azure_role_name" {
  value       = vault_azure_auth_backend_role.vault_eda_relay.role
  description = "Name of the Azure auth role for the relay"
}

output "vault_demo_user" {
  value       = "demo"
  description = "Demo user for testing"
}
