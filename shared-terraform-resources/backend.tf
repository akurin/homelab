terraform {
  backend "s3" {
    key     = "shared/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
    profile = "personal"
  }
}
