############################
# SSH Key
############################

resource "tls_private_key" "ansible" {
  algorithm = "ED25519"
}

resource "local_file" "ansible_private_key" {
  content         = tls_private_key.ansible.private_key_openssh
  filename        = "${path.module}/ansible_id_ed25519"
  file_permission = "0600"
}
