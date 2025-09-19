terraform {
  backend "s3" {
    bucket  = "tf-state-bucket-573446657092-us-east-1"
    key     = "vpn/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
    profile = "personal"
  }
}
