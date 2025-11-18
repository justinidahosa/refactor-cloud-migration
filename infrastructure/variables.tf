variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "project_name" {
  type    = string
  default = "refactor-cloud-migration"
}
variable "domain_name" {
  type = string
}
variable "hosted_zone_id" {
  type = string
}

# Networking
variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}
variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}
variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.11.0/24", "10.0.12.0/24"]
}

# App
variable "container_image" {
  type = string
} # e.g., <aws_account_id>.dkr.ecr.us-east-1.amazonaws.com/myapp:1.0.0
variable "container_port" {
  type    = number
  default = 3000
}
variable "desired_count" {
  type    = number
  default = 2
}
variable "health_check_path" {
  type    = string
  default = "/"
}

# DB
variable "db_engine" {
  type    = string
  default = "postgres"
} # or "mysql"
variable "db_engine_version" {
  type = string
}
variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}
variable "db_name" {
  type    = string
  default = "appdb"
}
variable "multi_az" {
  type    = bool
  default = true
}
variable "migration_bucket_name" {
  description = "Globally-unique S3 bucket name for migration dumps."
  type        = string
}
variable "tags" {
  description = "Common tags for all resources."
  type        = map(string)
  default = {
    Project   = "app-migration"
    ManagedBy = "terraform"
    Env       = "dev"
  }
}
