terraform {
  backend "s3" {
    key            = "homelab.tfstate"
    region         = "us-east-1"
    encrypt        = true
    profile        = "personal"
  }
}
