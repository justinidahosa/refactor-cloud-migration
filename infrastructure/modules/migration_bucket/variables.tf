variable "bucket_name" {
  description = "Globally-unique S3 bucket name for migration dumps (lowercase, 3–63 chars)."
  type        = string
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = {}
}
