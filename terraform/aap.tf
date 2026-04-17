############################
# Foundation
############################
resource "aap_organization" "vault_eda" {
  name = "Vault EDA Demo"
}

data "aap_credential_type" "machine" {
  name = "Machine"
  kind = "ssh"
}

resource "aap_credential" "ansible_ssh" {
  name            = "Vault EDA Demo SSH Credential"
  organization    = aap_organization.vault_eda.id
  credential_type = data.aap_credential_type.machine.id

  inputs = jsonencode({
    username     = "ansible"
    ssh_key_data = tls_private_key.ansible.private_key_openssh
  })
}

data "aap_credential_type" "vault" {
  name = "HashiCorp Vault Secret Lookup"
  kind = "external"
}

resource "aap_credential" "vault" {
  name            = "Vault EDA Demo Vault Credential"
  organization    = aap_organization.vault_eda.id
  credential_type = data.aap_credential_type.vault.id

  inputs = jsonencode({
    url               = hcp_vault_cluster.vault.vault_public_endpoint_url
    namespace         = hcp_vault_cluster.vault.namespace
    role_id           = vault_approle_auth_backend_role.aap.role_id
    secret_id         = vault_approle_auth_backend_role_secret_id.aap.secret_id
    api_version       = vault_mount.kv.type == "kv-v2" ? "v2" : "v1"
    default_auth_path = "approle"
  })
}

############################
# Inventory
############################

resource "aap_inventory" "ansible_targets" {
  name         = "Vault EDA Demo Inventory"
  organization = aap_organization.vault_eda.id
}

resource "aap_host" "ansible_vm" {
  name      = "Vault EDA Demo Host"
  inventory = aap_inventory.ansible_targets.id

  variables = yamlencode({
    ansible_host               = azurerm_public_ip.vm.ip_address
    ansible_user               = azurerm_linux_virtual_machine.vm.admin_username
    ansible_python_interpreter = "/usr/bin/python3"
  })
}

############################
# Automation Controller
############################

resource "aap_project" "vault_eda" {
  name         = "Vault EDA Demo"
  organization = aap_organization.vault_eda.id

  scm_type = "git"
  scm_url  = "https://github.com/lakrass/vault-eda-demo"
}

resource "aap_execution_environment" "ee" {
  name  = "Vault EDA Demo Execution Environment"
  image = var.aap_execution_environment
}

resource "aap_credential_type" "demo" {
  name = "Vault EDA Demo Credential Type"

  inputs = jsonencode({
    "fields" : [
      {
        "id" : "demo_secret",
        "label" : "Demo Secret",
        "type" : "string"
      }
    ],
    "required" : ["demo_secret"]
  })
  injectors = jsonencode({
    "extra_vars" : {
      "demo_secret" : "{{ demo_secret }}"
    }
  })
}

resource "aap_credential" "demo" {
  name            = "Vault EDA Demo Credential"
  organization    = aap_organization.vault_eda.id
  credential_type = aap_credential_type.demo.id
}

resource "aap_credential_input_sources" "demo" {
  input_field_name = "demo_secret"
  metadata = {
    "secret_backend" : vault_mount.kv.path
    "secret_key" : "demo_secret"
    "secret_path" : "demo-secret"
  }
  target_credential = aap_credential.demo.id
  source_credential = aap_credential.vault.id
}

resource "aap_job_template" "jt" {
  name    = "Vault EDA Demo Job Template"
  project = aap_project.vault_eda.id

  inventory             = aap_inventory.ansible_targets.id
  playbook              = var.eda_playbook_path
  execution_environment = aap_execution_environment.ee.id
}

resource "aap_job_template_credential" "jt_cred" {
  credential_ids = [
    aap_credential.ansible_ssh.id,
    aap_credential.demo.id
  ]
  job_template_id = aap_job_template.jt.id
}

############################
# EDA
############################

resource "aap_eda_project" "vault_eda" {
  name            = "Vault EDA Demo"
  organization_id = aap_organization.vault_eda.id

  scm_type = "git"
  url      = "https://github.com/lakrass/vault-eda-demo"
}

resource "aap_eda_decision_environment" "azure" {
  name            = "Vault EDA Demo Decision Environment"
  organization_id = aap_organization.vault_eda.id

  image_url   = var.eda_decision_environment
  pull_policy = "always"
}

resource "aap_eda_credential_type" "azure_service_bus" {
  name = "Azure Service Bus"

  inputs = jsonencode({
    "fields" : [
      {
        "id" : "servicebus_connection_string",
        "label" : "Service Bus Connection String",
        "type" : "string"
        "secret" : true
      }
    ],
    "required" : ["servicebus_connection_string"]
  })
  injectors = jsonencode({
    "extra_vars" : {
      "servicebus_connection_string" : "{{ servicebus_connection_string }}"
    }
  })
}

resource "aap_eda_credential" "azure_service_bus" {
  name            = "Vault EDA Demo Azure Service Bus Credential"
  organization_id = aap_organization.vault_eda.id

  credential_type_id = aap_eda_credential_type.azure_service_bus.id
  inputs = jsonencode({
    servicebus_connection_string = azurerm_servicebus_namespace_authorization_rule.sb_send.primary_connection_string
  })
}

#resource "rulebook activation" "name" {
#
#}

############################
# Outputs
############################

output "aap_inventory_id" {
  value = aap_inventory.ansible_targets.id
}

output "eda_project_id" {
  value = aap_eda_project.vault_eda.id
}
