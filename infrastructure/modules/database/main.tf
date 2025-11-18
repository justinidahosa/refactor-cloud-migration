# Subnet group
resource "aws_db_subnet_group" "this" {
  name       = "app-db-subnets"
  subnet_ids = var.private_subnet_ids
  tags       = { Name = "app-db-subnets" }
}

# Strong password for the application user
resource "random_password" "db_master" {
  length  = 20
  special = true
}

# Pick the right port by engine
locals {
  db_port_map = {
    postgres   = 5432
    postgresql = 5432
    mysql      = 3306
  }
  db_port = lookup(local.db_port_map, lower(var.db_engine), 5432)
}

# RDS instance
resource "aws_db_instance" "this" {
  identifier                  = "app-db"
  engine                      = var.db_engine            
  engine_version              = var.db_engine_version         
  instance_class              = var.db_instance_class        
  allocated_storage           = 20
  storage_type                = "gp3"

  db_name                     = var.db_name                   # e.g., "appdb"
  username                    = "appuser"
  password                    = random_password.db_master.result
  port                        = local.db_port

  vpc_security_group_ids      = [var.rds_sg_id]
  db_subnet_group_name        = aws_db_subnet_group.this.name
  multi_az                    = var.multi_az
  publicly_accessible         = false

  backup_retention_period     = 7
  auto_minor_version_upgrade  = true
  deletion_protection         = false
  copy_tags_to_snapshot       = true
  skip_final_snapshot         = true

  tags = {
    Name = "app-db"
  }
}

resource "aws_secretsmanager_secret" "appdb" {
  name                      = var.secret_name               
  recovery_window_in_days   = 7
  description               = "App DB connection for RDS (used by ECS/CodeBuild)"
}

resource "aws_secretsmanager_secret_version" "appdb" {
  secret_id = aws_secretsmanager_secret.appdb.id

  secret_string = jsonencode({
    host     = aws_db_instance.this.address
    port     = local.db_port
    dbname   = var.db_name
    username = "appuser"
    password = random_password.db_master.result
    DB_HOST  = aws_db_instance.this.address
    DB_PORT  = local.db_port
    DB_NAME  = var.db_name
    DB_USER  = "appuser"
    DB_PASS  = random_password.db_master.result
  })
}