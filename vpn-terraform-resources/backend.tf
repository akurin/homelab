terraform {
  backend "s3" {
    key     = "vpn/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
    profile = "personal"
  }
}
