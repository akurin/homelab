terraform {
  required_providers {
    vultr = {
      source  = "vultr/vultr"
      version = "2.9.0"
    }
  }
}

provider "vultr" {
}
