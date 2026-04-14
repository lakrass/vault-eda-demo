############################
# Foundation
############################
resource "aap_organization" "vault_eda" {
  name = "vault-eda-demo"
}

data "aap_credential_type" "machine" {
  name = "Machine"
  kind = "ssh"
}

resource "aap_credential" "ansible_ssh" {
  name            = "vault-eda-demo"
  organization    = aap_organization.vault_eda.id
  credential_type = data.aap_credential_type.machine.id

  inputs = jsonencode({
    username     = "ansible"
    ssh_key_data = tls_private_key.ansible.private_key_openssh
  })
}

############################
# AAP Inventory
############################

resource "aap_inventory" "ansible_targets" {
  name         = "vault-eda-demo"
  organization = aap_organization.vault_eda.id
}

resource "aap_host" "ansible_vm" {
  name      = "vault-eda-demo"
  inventory = aap_inventory.ansible_targets.id

  variables = yamlencode({
    ansible_host               = azurerm_public_ip.vm.ip_address
    ansible_user               = azurerm_linux_virtual_machine.vm.admin_username
    ansible_python_interpreter = "/usr/bin/python3"
  })
}

############################
# EDA Project
############################

resource "aap_eda_project" "vault_eda" {
  name            = "vault-eda-demo"
  organization_id = aap_organization.vault_eda.id

  scm_type = "git"
  url      = var.eda_project_scm_url
}

resource "aap_eda_decision_environment" "vault" {
  name            = "eda-azure-vault"
  organization_id = aap_organization.vault_eda.id

  image_url   = var.eda_decision_environment
  pull_policy = "always"
}

############################
# Outputs
############################

output "aap_inventory_id" {
  value = aap_inventory.ansible_targets.id
}

output "eda_project_id" {
  value = aap_eda_project.vault_eda.id
}
