variable "vpc_id"             { 
    type = string 
}
variable "private_subnet_ids" { 
    type = list(string) 
}
variable "rds_sg_id"          { 
    type = string 
}
variable "db_engine"          { 
    type = string 
}
variable "db_instance_class"  { 
    type = string 
}
variable "db_name"            { 
    type = string 
}
variable "multi_az"           { 
    type = bool 
}
variable "secret_name" {
  type        = string
  default     = "appdb-connection"
  description = "Secrets Manager name for the app DB connection JSON"
}
variable "db_engine_version"  { 
    type = string 
}