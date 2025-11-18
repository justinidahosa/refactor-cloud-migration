terraform {
  backend "s3" {
    bucket         = "refactor-cloud-migration-tf-state"
    key            = "backend/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "refactor-cloud-migration-tf-locks"
    encrypt        = true
  }
}
