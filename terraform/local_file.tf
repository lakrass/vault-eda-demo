resource "local_file" "env_file" {
  filename = "${path.module}/../.env"
  content  = <<-EOF
    VAULT_ADDR=${hcp_vault_cluster.vault.vault_public_endpoint_url}
    VAULT_NAMESPACE=${hcp_vault_cluster.vault.namespace}
    VAULT_AZURE_ROLE=${vault_azure_auth_backend_role.vault_eda_relay.role}
    SERVICEBUS_CONNECTION=${azurerm_servicebus_namespace_authorization_rule.sb_send.primary_connection_string}
    SERVICEBUS_QUEUE=${azurerm_servicebus_queue.queue.name}
  EOF
}
