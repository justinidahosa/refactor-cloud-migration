variable "domain_name"    { 
    type = string 
}
variable "hosted_zone_id" { 
    type = string 
}
variable "alb_dns_name"   { 
    type = string 
}
variable "alb_zone_id"    { 
    type = string 
}
variable "create_www"     { 
    type = bool 
    default = true 
}
