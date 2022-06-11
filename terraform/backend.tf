terraform {
  backend "s3" {
    bucket         = "tf-state-bucket-573446657092-us-east-1"
    key            = "homelab.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tf-state-table-573446657092"
    encrypt        = true
    profile        = "personal"
  }
}
