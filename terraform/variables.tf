variable "hcloud_token" {
}

variable "location" {
  default = "hel1"
}

variable "instances" {
  default = "1"
}

variable "server_type" {
  default = "cpx11"
}

variable "os_type" {
  default = "ubuntu-20.04"
}

variable "disk_size" {
  default = "40"
}

variable "ip_range" {
  default = "10.0.1.0/24"
}
