resource "vultr_ssh_key" "default" {
  name    = "v2"
  ssh_key = file("~/.ssh/id_ed25519.pub")

  # This is a workaround to prevent the SSH key from being updated every time
  lifecycle {
    ignore_changes = [ssh_key]
  }
}
