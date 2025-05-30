variable "ssh_key_id" {
  type = string
}

variable "region" {
  default = "lhr"
}

variable "agent_plan" {
  default = "vc2-1c-2gb"
}

variable "server_plan" {
  default = "vc2-1c-2gb"
}

variable "os_id" {
  default = 387
}

variable "disk_size" {
  default = "40"
}
