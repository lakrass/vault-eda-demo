resource "local_file" "ansible_private_key" {
  content         = tls_private_key.ansible.private_key_openssh
  filename        = "${path.module}/../ansible_id_ed25519.key"
  file_permission = "0600"
}


resource "local_file" "env_file" {
  filename = "${path.module}/../.env"
  content  = <<-EOF
    VAULT_ADDR=${hcp_vault_cluster.vault.vault_public_endpoint_url}
    VAULT_NAMESPACE=${hcp_vault_cluster.vault.namespace}
    VAULT_AZURE_ROLE=${vault_azure_auth_backend_role.vault_eda_relay.role}
    SERVICEBUS_CONNECTION=${azurerm_servicebus_namespace_authorization_rule.sb_send.primary_connection_string}
    SERVICEBUS_QUEUE=${azurerm_servicebus_queue.queue.name}
    AZURE_SUBSCRIPTION_ID=${data.azurerm_client_config.current.subscription_id}
    AZURE_RESOURCE_GROUP_NAME=${azurerm_resource_group.rg.name}
  EOF
}
