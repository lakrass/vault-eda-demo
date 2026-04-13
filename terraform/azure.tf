############################
# Foundation
############################

resource "azurerm_resource_group" "rg" {
  name     = "vault-eda-demo"
  location = var.location
}

resource "azurerm_storage_account" "sa" {
  name                     = "stvaultfn${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
}

resource "azurerm_service_plan" "plan" {
  name                = "vault-eda-demo"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Linux"
  sku_name            = "P1v3" # Always-on (for WS-Connection)
}

resource "azurerm_application_insights" "ai" {
  name                = "vault-eda-demo"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "web"
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

  max_delivery_count = 10
}

resource "azurerm_servicebus_namespace_authorization_rule" "sb_send" {
  name         = "send-only"
  namespace_id = azurerm_servicebus_namespace.sb.id

  listen = false
  send   = true
  manage = false
}

############################
# Azure Function App (WS client + SB sender)
############################

resource "azurerm_linux_function_app" "fn" {
  name                       = "vault-eda-demo"
  resource_group_name        = azurerm_resource_group.rg.name
  location                   = azurerm_resource_group.rg.location
  service_plan_id            = azurerm_service_plan.plan.id
  storage_account_name       = azurerm_storage_account.sa.name
  storage_account_access_key = azurerm_storage_account.sa.primary_access_key

  app_settings = {
    # Vault
    VAULT_ADDR = hcp_vault_cluster.vault.vault_public_endpoint_url

    # Service Bus
    SERVICEBUS_CONNECTION = azurerm_servicebus_namespace_authorization_rule.sb_send.primary_connection_string
    SERVICEBUS_QUEUE      = azurerm_servicebus_queue.queue.name

    # AAP / EDA Event Stream target
    AAP_EVENT_STREAM_URL   = ""
    AAP_EVENT_STREAM_TOKEN = ""

    # Runtime
    FUNCTIONS_WORKER_RUNTIME = "python"
  }

  site_config {
    application_stack {
      python_version = "3.11"
    }

    application_insights_key = azurerm_application_insights.ai.instrumentation_key
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
    offer     = "0001-com-ubuntu-server-noble"
    sku       = "24_04-lts-gen2"
    version   = "latest"
  }
}

output "ansible_vm_public_ip" {
  value = azurerm_public_ip.vm.ip_address
}
