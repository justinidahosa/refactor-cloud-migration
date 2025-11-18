variable "project_name"      { 
    type = string 
}
variable "sns_email"         { 
    type = string
    default = ""
}

variable "ecs_cluster_name"  { 
    type = string 
}
variable "ecs_service_name"  { 
    type = string 
}
variable "alb_arn_suffix"    { 
    type = string 
}
variable "tg_arn_suffix"     { 
    type = string 
}
variable "db_identifier"     { 
    type = string 
}
variable "log_group_name"    { 
    type = string 
}
