resource "aws_security_group" "alb" {
  name        = "alb-sg"
  description = "Allow HTTP/HTTPS from anywhere"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress { 
    from_port = 80  
    to_port = 80  
    protocol = "tcp" 
    cidr_blocks = ["0.0.0.0/0"] 
    }
  ingress { 
    from_port = 443 
    to_port = 443 
    protocol = "tcp" 
    cidr_blocks = ["0.0.0.0/0"] 
    }

  tags = { 
    Name = "alb-sg" 
    }
}

# 2) ECS SG: only ALB can talk to tasks on container_port
resource "aws_security_group" "ecs" {
  name        = "ecs-sg"
  description = "Allow ALB to talk to ECS tasks"
  vpc_id      = var.vpc_id

  egress { 
    from_port = 0 
    to_port = 0 
    protocol = "-1" 
    cidr_blocks = ["0.0.0.0/0"] 
    }

  tags = { 
    Name = "ecs-sg" 
    }
}

resource "aws_security_group_rule" "ecs_in_from_alb" {
  type                     = "ingress"
  security_group_id        = aws_security_group.ecs.id
  from_port                = var.container_port
  to_port                  = var.container_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
}

# 3) RDS SG: only ECS can talk to DB port
resource "aws_security_group" "rds" {
  name        = "rds-sg"
  description = "Allow ECS to reach DB"
  vpc_id      = var.vpc_id

  egress { 
    from_port = 0 
    to_port = 0 
    protocol = "-1" 
    cidr_blocks = ["0.0.0.0/0"] 
    }
  tags = { 
    Name = "rds-sg" }
}

# Defaults for Postgres/MySQL
locals {
  db_port = 5432
}

resource "aws_security_group_rule" "rds_in_from_ecs" {
  type                     = "ingress"
  security_group_id        = aws_security_group.rds.id
  from_port                = local.db_port
  to_port                  = local.db_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs.id
}
