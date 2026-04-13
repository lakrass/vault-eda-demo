############################
# SSH Key
############################

resource "tls_private_key" "ansible" {
  algorithm = "ED25519"
}
