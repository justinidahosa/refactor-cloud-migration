# Data (identity & region)
data "aws_region" "current" {}
data "aws_caller_identity" "me" {}

# ALB
resource "aws_lb" "app" {
  name               = "app-alb"
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids
}

resource "aws_lb_target_group" "tg" {
  name        = "app-tg"
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    path                = var.health_check_path
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 15
    matcher             = "200-399"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-Ext1-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}


# ECS Cluster

resource "aws_ecs_cluster" "this" {
  name = "app-cluster"
}

# IAM (least-privilege)

# Assume role policy for ECS tasks
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Execution role (image pulls, logs)
resource "aws_iam_role" "task_execution" {
  name               = "ecsTaskExecutionRole"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

# Preferred: managed execution policy
resource "aws_iam_role_policy_attachment" "exec_attach_managed" {
  count      = var.use_managed_exec_policy ? 1 : 0
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "exec_ecr_pull" {
  count = var.use_managed_exec_policy ? 0 : 1
  name  = "ExecEcrPull"
  role  = aws_iam_role.task_execution.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      {
        Effect = "Allow",
        Action = ["ecr:BatchCheckLayerAvailability","ecr:GetDownloadUrlForLayer","ecr:BatchGetImage"],
        Resource = "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.me.account_id}:repository/${var.ecr_repo_name}"
      }
    ]
  })
}

resource "aws_iam_role_policy" "exec_cwlogs" {
  count = var.use_managed_exec_policy ? 0 : 1
  name  = "ExecCloudWatchLogs"
  role  = aws_iam_role.task_execution.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["logs:CreateLogStream","logs:PutLogEvents","logs:DescribeLogStreams"],
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.me.account_id}:log-group:${aws_cloudwatch_log_group.app.name}:*"
      }
    ]
  })
}

# Task role (app runtime permissions)
resource "aws_iam_role" "task_role" {
  name               = "ecsTaskRole"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}


# S3 uploads limited to one bucket + prefix (e.g., uploads/*)
resource "aws_iam_role_policy" "app_s3_uploads" {
  count = var.enable_s3_uploads ? 1 : 0

  name = "${var.project_name}-app-s3-uploads"
  role = aws_iam_role.task_role.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["s3:ListBucket"],
        Resource = var.s3_bucket_arn,          # arn:aws:s3:::bucket
        Condition = {
          StringLike = {
            "s3:prefix" = [ var.s3_prefix ]    # e.g., "uploads/*"
          }
        }
      },
      {
        Effect   = "Allow",
        Action   = ["s3:PutObject","s3:GetObject","s3:PutObjectAcl"],
        Resource = "${var.s3_bucket_arn}/${var.s3_prefix}" # arn:aws:s3:::bucket/uploads/*
      }
    ]
  })
}

# Read exactly one secret (DB creds)
resource "aws_iam_role_policy" "app_secret_read" {
  count = var.enable_secret_read ? 1 : 0

  name = "${var.project_name}-app-secret-read"
  role = aws_iam_role.task_role.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["secretsmanager:GetSecretValue"],
      Resource = var.secret_arn,
      Condition = {
        "ForAnyValue:StringEquals" = {
          "secretsmanager:VersionStage" = ["AWSCURRENT"]
        }
      }
    }]
  })
}

# Decrypt using one specific KMS key
resource "aws_iam_role_policy" "app_kms_decrypt" {
  count = var.enable_kms_decrypt ? 1 : 0

  name = "${var.project_name}-app-kms-decrypt"
  role = aws_iam_role.task_role.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["kms:Decrypt","kms:GenerateDataKey"],
      Resource = var.kms_key_arn
    }]
  })
}


# Logging
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/app"
  retention_in_days = 14
}

# Task Definition
resource "aws_ecs_task_definition" "app" {
  family                   = "app-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name  = "app",
      image = var.container_image,
      portMappings = [{
        containerPort = var.container_port,
        protocol      = "tcp"
      }],
      environment = var.environment,
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app.name,
          awslogs-region        = data.aws_region.current.name,
          awslogs-stream-prefix = "ecs"
        }
      },
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}${var.health_check_path} || exit 1"],
        interval    = 30,
        retries     = 3,
        startPeriod = 30,
        timeout     = 5
      }
    }
  ])
}

# -------------------------
# Service
# -------------------------
resource "aws_ecs_service" "app" {
  name            = "app-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_sg_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tg.arn
    container_name   = "app"
    container_port   = var.container_port
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  depends_on = [aws_lb_listener.https]
}
