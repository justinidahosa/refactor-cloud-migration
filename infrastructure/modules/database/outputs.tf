output "db_endpoint"      { 
    value = aws_db_instance.this.address 
}
output "db_port"          { 
    value = local.db_port 
}
output "app_db_password"  { 
    value = random_password.db_master.result  
    sensitive = true 
}
output "db_identifier" { 
    value = aws_db_instance.this.id 
}
output "appdb_secret_arn" {
  value = aws_secretsmanager_secret.appdb.arn
}

