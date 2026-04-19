############################
# Foundation
############################

resource "azurerm_resource_group" "rg" {
  name     = "vault-eda-demo"
  location = var.location
}

resource "azurerm_user_assigned_identity" "umi" {
  name                = "vault-eda-demo"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_log_analytics_workspace" "law" {
  name                = "vault-eda-demo"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_container_app_environment" "env" {
  name                       = "vault-eda-demo"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
}

resource "azurerm_application_insights" "ai" {
  name                = "vault-eda-demo"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  application_type = "web"
  workspace_id     = azurerm_log_analytics_workspace.law.id
}

############################
# Service Bus
############################

resource "azurerm_servicebus_namespace" "sb" {
  name                = "vault-eda-demo"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
}

resource "azurerm_servicebus_queue" "queue" {
  name         = "vault-events"
  namespace_id = azurerm_servicebus_namespace.sb.id

  requires_duplicate_detection         = true
  lock_duration                        = "PT10S"
  dead_lettering_on_message_expiration = true
}

resource "azurerm_servicebus_namespace_authorization_rule" "sb_send" {
  name         = "send-only"
  namespace_id = azurerm_servicebus_namespace.sb.id

  listen = false
  send   = true
  manage = false
}

resource "azurerm_servicebus_namespace_authorization_rule" "sb_listen" {
  name         = "listen-only"
  namespace_id = azurerm_servicebus_namespace.sb.id

  listen = true
  send   = false
  manage = false
}

############################
# Azure Container App (WS client + SB sender)
############################

resource "azurerm_container_app" "app" {
  name                         = "vault-eda-demo"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.umi.id]
  }

  template {
    min_replicas = 2

    container {
      name   = "vault-eda-relay"
      image  = var.azure_container_app_image
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "VAULT_ADDR"
        value = hcp_vault_cluster.vault.vault_public_endpoint_url
      }

      env {
        name  = "VAULT_NAMESPACE"
        value = hcp_vault_cluster.vault.namespace
      }

      env {
        name  = "VAULT_AZURE_ROLE"
        value = vault_azure_auth_backend_role.vault_eda_relay.role
      }

      env {
        name  = "SERVICEBUS_CONNECTION"
        value = azurerm_servicebus_namespace_authorization_rule.sb_send.primary_connection_string
      }

      env {
        name  = "SERVICEBUS_QUEUE"
        value = azurerm_servicebus_queue.queue.name
      }

      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.umi.client_id
      }

      env {
        name  = "AZURE_SUBSCRIPTION_ID"
        value = data.azurerm_client_config.current.subscription_id
      }

      env {
        name  = "AZURE_RESOURCE_GROUP_NAME"
        value = azurerm_resource_group.rg.name
      }

      liveness_probe {
        transport        = "HTTP"
        path             = "/livez"
        port             = 8080
        initial_delay    = 5
        interval_seconds = 10
      }

      readiness_probe {
        transport        = "HTTP"
        path             = "/readyz"
        port             = 8080
        initial_delay    = 5
        interval_seconds = 10
      }
    }
  }
}

############################
# Network
############################

resource "azurerm_virtual_network" "vnet" {
  name                = "vault-eda-demo"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.10.0.0/16"]
}

resource "azurerm_subnet" "subnet" {
  name                 = "vault-eda-demo"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.1.0/24"]
}

############################
# NSG (SSH access)
############################

resource "azurerm_network_security_group" "nsg" {
  name                = "vault-eda-demo"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "nsg_assoc" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

############################
# Public IP + NIC
############################

resource "azurerm_public_ip" "vm" {
  name                = "vault-eda-demo"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "vm" {
  name                = "vault-eda-demo-ssh"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm.id
  }
}

############################
# Linux VM
############################

resource "azurerm_linux_virtual_machine" "vm" {
  name                = "vault-eda-demo"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  network_interface_ids = [
    azurerm_network_interface.vm.id
  ]

  size            = "Standard_D2s_v3"
  priority        = "Spot"
  eviction_policy = "Deallocate"

  admin_username = "ansible"

  disable_password_authentication = true

  admin_ssh_key {
    username   = "ansible"
    public_key = tls_private_key.ansible.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}

############################
# Outputs
############################

output "ansible_vm_public_ip" {
  value = azurerm_public_ip.vm.ip_address
}

output "servicebus_connection" {
  value       = azurerm_servicebus_namespace_authorization_rule.sb_send.primary_connection_string
  description = "Primary connection string for Service Bus"
  sensitive   = true # Mark as sensitive since it contains credentials
}

output "servicebus_queue" {
  value       = azurerm_servicebus_queue.queue.name
  description = "Name of the Service Bus queue"
}

