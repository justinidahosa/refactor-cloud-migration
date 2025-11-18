terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.aws_region
}

# -----------------------------
# Networking, Security, Certs, Repo, Database
# -----------------------------

module "network" {
  source               = "./modules/network"
  project_name         = var.project_name
  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

module "security" {
  source         = "./modules/security"
  vpc_id         = module.network.vpc_id
  container_port = var.container_port
}

module "acm" {
  source         = "./modules/acm"
  domain_name    = var.domain_name
  hosted_zone_id = var.hosted_zone_id
}

module "ecr" {
  source = "./modules/ecr"
  name   = "${var.project_name}-repo"
}

module "database" {
  source             = "./modules/database"
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  rds_sg_id          = module.security.rds_sg_id

  db_engine         = var.db_engine
  db_engine_version = var.db_engine_version
  db_instance_class = var.db_instance_class
  db_name           = var.db_name
  multi_az          = var.multi_az
}

# -----------------------------
# Compute (ALB + ECS Fargate)
# -----------------------------

module "compute" {
  source             = "./modules/compute"
  project_name       = var.project_name
  vpc_id             = module.network.vpc_id
  public_subnet_ids  = module.network.public_subnet_ids
  private_subnet_ids = module.network.private_subnet_ids
  alb_sg_id          = module.security.alb_sg_id
  ecs_sg_id          = module.security.ecs_sg_id
  certificate_arn    = module.acm.certificate_arn

  container_image   = var.container_image
  container_port    = var.container_port
  desired_count     = var.desired_count
  health_check_path = var.health_check_path

  environment = [
    { name = "DB_HOST",      value = module.database.db_endpoint },
    { name = "DB_PORT",      value = tostring(module.database.db_port) },
    { name = "DB_NAME",      value = var.db_name },
    { name = "DB_USER",      value = "appuser" },
    { name = "DB_PASS",      value = module.database.app_db_password },
    { name = "DB_PASSWORD",  value = module.database.app_db_password },
    { name = "STORAGE",      value = "db" },
    { name = "STORAGE_MODE", value = "db" }
  ]

  # IAM toggles inside compute module
  use_managed_exec_policy = true
  enable_secret_read      = true
  secret_arn              = module.database.appdb_secret_arn
  enable_s3_uploads       = false
  enable_kms_decrypt      = false
}

# -----------------------------
# DNS + Monitoring
# -----------------------------

module "route53" {
  source         = "./modules/route53"
  domain_name    = var.domain_name
  hosted_zone_id = var.hosted_zone_id
  alb_dns_name   = module.compute.alb_dns_name
  alb_zone_id    = module.compute.alb_zone_id
  create_www     = true
}

module "monitoring" {
  source       = "./modules/monitoring"
  project_name = var.project_name
  sns_email    = "" # optional; add a real email to subscribe

  ecs_cluster_name = module.compute.ecs_cluster_name
  ecs_service_name = module.compute.ecs_service_name
  alb_arn_suffix   = module.compute.alb_arn_suffix
  tg_arn_suffix    = module.compute.tg_arn_suffix

  db_identifier  = module.database.db_identifier
  log_group_name = module.compute.log_group_name
}

# -----------------------------
# App S3 uploads bucket
# -----------------------------

module "s3_uploads" {
  source      = "./modules/s3_uploads"
  bucket_name = "${var.project_name}-uploads"
}

module "migration_bucket" {
  source      = "./modules/migration_bucket"
  bucket_name = var.migration_bucket_name
  tags        = var.tags
}

# -----------------------------
# CodeBuild plumbing (SG/Role/Policy)
# -----------------------------

# SG that CodeBuild ENIs will use inside your VPC
resource "aws_security_group" "cb" {
  name   = "${var.project_name}-codebuild-sg"
  vpc_id = module.network.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-codebuild-sg" }
}

# Allow CodeBuild to reach RDS on 5432
resource "aws_security_group_rule" "rds_from_cb" {
  type                     = "ingress"
  security_group_id        = module.security.rds_sg_id
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.cb.id
  description              = "CodeBuild restore to RDS 5432"
}

# IAM trust for CodeBuild
data "aws_iam_policy_document" "cb_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

# CodeBuild service role
resource "aws_iam_role" "cb" {
  name               = "${var.project_name}-codebuild-role"
  assume_role_policy = data.aws_iam_policy_document.cb_assume.json
}

# Least-privileged inline policy for CodeBuild (VPC + S3 + Secrets + Logs)
resource "aws_iam_role_policy" "cb_inline" {
  name = "${var.project_name}-codebuild-inline"
  role = aws_iam_role.cb.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # S3 read (dump file)
      {
        Effect   = "Allow",
        Action   = ["s3:ListBucket"],
        Resource = "arn:aws:s3:::${var.migration_bucket_name}"
      },
      {
        Effect   = "Allow",
        Action   = ["s3:GetObject"],
        Resource = "arn:aws:s3:::${var.migration_bucket_name}/*"
      },
      # Secrets read (DB creds secret)
      {
        Effect   = "Allow",
        Action   = ["secretsmanager:GetSecretValue"],
        Resource = module.database.appdb_secret_arn
      },
      # CloudWatch logs
      {
        Effect   = "Allow",
        Action   = ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents","logs:DescribeLogStreams"],
        Resource = "*"
      },
      # VPC ENI attach/describe for CodeBuild in VPC
      {
        Effect = "Allow",
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:CreateNetworkInterfacePermission",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeVpcs",
          "ec2:DescribeDhcpOptions",
          "ec2:DescribeRouteTables",
          "ec2:DescribeAvailabilityZones"
        ],
        Resource = "*"
      }
    ]
  })
}

# -----------------------------
# CodeBuild buildspecs
# -----------------------------

# Restore buildspec (your existing, with idempotency guard)
locals {
  buildspec_restore = <<-YAML
    version: 0.2
    phases:
      install:
        commands:
          - echo "Installing PostgreSQL 18 client + jq on Ubuntu (standard:7.0)..."
          - apt-get update -y
          - apt-get install -y wget gnupg2 lsb-release jq
          - sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
          - wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
          - apt-get update -y
          - apt-get install -y postgresql-client-18
          - pg_restore --version
      build:
        commands:
          - set -e
          - echo "Downloading dump from S3 s3://$MIG_BUCKET/db/app.dump"
          - aws s3 cp "s3://$MIG_BUCKET/db/app.dump" /tmp/app.dump
          - echo "Fetching DB password from Secrets Manager"
          - SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "$DB_SECRET_ARN" --query SecretString --output text)
          - export PGPASSWORD=$(echo "$SECRET_JSON" | jq -r '.DB_PASS // .password // .db_pass')

          # ---------- Idempotency guard ----------
          - echo "Checking if DB already initialized..."
          - |
            if psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -tAc \
              "SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='notes' LIMIT 1;" | grep -q 1; then
              echo "DB already initialized — skipping restore."; exit 0
            fi
          # --------------------------------------

          - echo "Restoring into $DB_HOST/$DB_NAME as $DB_USER ..."
          - pg_restore -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -Fc --no-owner --no-privileges /tmp/app.dump
          - echo "Restore complete."
    artifacts:
      files:
        - '**/*'
  YAML
}

# NEW: Smoke-check buildspec (prints COUNT(*))
locals {
  buildspec_smoke = <<-YAML
    version: 0.2
    phases:
      install:
        commands:
          - echo "Installing PostgreSQL client + jq for smoke check..."
          - apt-get update -y
          - apt-get install -y wget gnupg2 lsb-release jq
          - sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
          - wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
          - apt-get update -y
          - apt-get install -y postgresql-client-18
      build:
        commands:
          - set -e
          - SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "$DB_SECRET_ARN" --query SecretString --output text)
          - export PGPASSWORD=$(echo "$SECRET_JSON" | jq -r '.DB_PASS // .password // .db_pass')
          - echo "Rows in public.notes:"
          - psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM public.notes;" || true
  YAML
}

# -----------------------------
# CodeBuild Projects
# -----------------------------

resource "aws_codebuild_project" "restore" {
  name         = "${var.project_name}-db-restore"
  service_role = aws_iam_role.cb.arn

  source {
    type      = "NO_SOURCE"
    buildspec = local.buildspec_restore
  }

  artifacts { type = "NO_ARTIFACTS" }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = false

    environment_variable { 
      name = "MIG_BUCKET"    
      value = var.migration_bucket_name 
      }
    environment_variable { 
      name = "DB_HOST"       
      value = module.database.db_endpoint 
      }
    environment_variable { 
      name = "DB_NAME"       
      value = var.db_name 
      }
    environment_variable { 
      name = "DB_USER"       
      value = "appuser" 
      }
    environment_variable { 
      name = "DB_SECRET_ARN" 
      value = module.database.appdb_secret_arn 
      }
  }

  vpc_config {
    vpc_id             = module.network.vpc_id
    subnets            = module.network.private_subnet_ids
    security_group_ids = [aws_security_group.cb.id]
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/codebuild/${var.project_name}-db-restore"
      stream_name = "build"
    }
  }
}

# NEW: one-shot smoke query project
resource "aws_codebuild_project" "smoke" {
  name         = "${var.project_name}-db-smoke"
  service_role = aws_iam_role.cb.arn

  source {
    type      = "NO_SOURCE"
    buildspec = local.buildspec_smoke
  }

  artifacts { type = "NO_ARTIFACTS" }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = false

    environment_variable { 
      name = "DB_HOST"       
      value = module.database.db_endpoint 
      }
    environment_variable { 
      name = "DB_NAME"       
      value = var.db_name 
      }
    environment_variable { 
      name = "DB_USER"       
      value = "appuser" 
      }
    environment_variable { 
      name = "DB_SECRET_ARN" 
      value = module.database.appdb_secret_arn 
      }
  }

  vpc_config {
    vpc_id             = module.network.vpc_id
    subnets            = module.network.private_subnet_ids
    security_group_ids = [aws_security_group.cb.id]
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/codebuild/${var.project_name}-db-smoke"
      stream_name = "build"
    }
  }
}

