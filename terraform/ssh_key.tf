resource "hcloud_ssh_key" "default" {
  name       = "v2"
  public_key = file("~/.ssh/id_ed25519.pub")
}
