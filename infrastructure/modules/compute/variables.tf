variable "project_name"       { type = string }
variable "vpc_id"             { type = string }
variable "public_subnet_ids"  { type = list(string) }
variable "private_subnet_ids" { type = list(string) }

variable "alb_sg_id"          { type = string }
variable "ecs_sg_id"          { type = string }
variable "certificate_arn"    { type = string }

variable "container_image"    { type = string }   # e.g. 123456789012.dkr.ecr.us-east-1.amazonaws.com/repo:1.0.0
variable "container_port"     { type = number }   # e.g. 3000
variable "desired_count"      { type = number }   # e.g. 2
variable "health_check_path"  { type = string }   # e.g. "/healthz"

# ENV for the container (BEGINNER-FRIENDLY: simple list of name/value)
variable "environment" {
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

# ===== Execution role policy selection =====
# If true, attach AWS managed policy AmazonECSTaskExecutionRolePolicy
# If false, attach minimal inline permissions for ECR + CloudWatch Logs (needs ecr_repo_name)
variable "use_managed_exec_policy" {
  type    = bool
  default = true
}

# Needed only when use_managed_exec_policy = false
variable "ecr_repo_name" {
  description = "ECR repository name (not URI). Required only if use_managed_exec_policy = false."
  type        = string
  default     = ""
}

# App (task role) runtime permissions

# Secrets Manager (read exactly one secret, e.g., DB creds)
variable "enable_secret_read" {
  description = "Allow the task to read a single Secrets Manager secret."
  type        = bool
  default     = true
}
variable "secret_arn" {
  description = "ARN of the secret the task may read (required if enable_secret_read = true)."
  type        = string
  default     = ""
}

# S3 uploads (limit to one bucket + prefix)
variable "enable_s3_uploads" {
  description = "Allow the task to read/write objects in one S3 bucket prefix (for user uploads)."
  type        = bool
  default     = false
}
variable "s3_bucket_arn" {
  description = "Target S3 bucket ARN (arn:aws:s3:::bucket-name). Used only if enable_s3_uploads = true."
  type        = string
  default     = ""
}
variable "s3_prefix" {
  description = "Key prefix inside the bucket for object access (e.g., \"uploads/*\")."
  type        = string
  default     = "uploads/*"
}

# KMS decrypt
variable "enable_kms_decrypt" {
  description = "Allow the task to decrypt with one specific KMS key."
  type        = bool
  default     = false
}
variable "kms_key_arn" {
  description = "KMS Key ARN (required if enable_kms_decrypt = true)."
  type        = string
  default     = ""
}
