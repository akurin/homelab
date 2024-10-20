resource "vultr_ssh_key" "default" {
  name    = "v2"
  ssh_key = file("~/.ssh/id_ed25519.pub")
}
