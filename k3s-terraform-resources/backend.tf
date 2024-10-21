terraform {
  backend "s3" {
    key     = "k3s/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
    profile = "personal"
  }
}
