terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  required_version = ">= 1.2.0"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
    account_id = data.aws_caller_identity.current.account_id
    aws_region = data.aws_region.current.name
}

provider "aws" {
  region  = "us-west-2"
  profile = "terraform-user"
}

# Create ECR Repository
resource "aws_ecr_repository" "practice_ecr_repo" {
  name                 = "practice-ecr-repo"
  image_tag_mutability = "MUTABLE"
}

output "practice_repository_url" {
  description = "Repository URL for practice-ecr-repo"
  value       = aws_ecr_repository.practice_ecr_repo.repository_url
}

# Create S3 bucket for artifacts
resource "aws_s3_bucket" "artifact_store" {
  bucket = "practice-artifact-store"
}

resource "aws_s3_bucket_public_access_block" "artifact_store_block" {
  bucket = aws_s3_bucket.artifact_store.bucket

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


# Create CodeBuild project
resource "aws_codebuild_project" "practice_build" {
  name         = "practice-codebuild-project"
  service_role = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:3.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true

    environment_variable {
      name  = "ECR_REPO_URI"
      value = aws_ecr_repository.practice_ecr_repo.repository_url
    }

    environment_variable {
      name = "CONTAINER_NAME"
      value = "practice-app"
    }
  }

  source {
    type = "CODEPIPELINE"
  }
}


# Create CodePipeline
resource "aws_codepipeline" "practice_pipeline" {
  name     = "practice-codepipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.artifact_store.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn = aws_codestarconnections_connection.github_connection.arn
        FullRepositoryId = "cgmill/deploy-practice"
        BranchName = "main"
      } 
    }
  }

  stage {
    name = "Build"

    action {
      name            = "Build"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["source_output"]
      output_artifacts = ["build_output"]
      version         = "1"

      configuration = {
        ProjectName = aws_codebuild_project.practice_build.name
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      input_artifacts = ["build_output"]
      version         = "1"

      configuration = {
        ClusterName = aws_ecs_cluster.practice_cluster.name
        ServiceName = aws_ecs_service.practice_service.name
        FileName    = "imagedefinitions.json"
        DeploymentTimeout = "10" # Might just be DeploymentTimeout
      }
    }
  }
}

# IAM roles and policies would need to be defined here
# (CodeBuild role, CodePipeline role, EC2 instance role)

# IAM role for CodeBuild
resource "aws_iam_role" "codebuild_role" {
  name = "practice-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_policy" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeBuildAdminAccess"
}

# IAM role for CodePipeline
resource "aws_iam_role" "codepipeline_role" {
  name = "practice-codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
      }
    ]
  })
}

data "aws_iam_policy_document" "codepipeline_ecs_policy" {
  statement {
    actions = [
      "ecs:*"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "codepipeline_ecs_policy" {
  name = "practice-codepipeline-ecs-policy"
  role = aws_iam_role.codepipeline_role.id
  policy = data.aws_iam_policy_document.codepipeline_ecs_policy.json
}

data "aws_iam_policy_document" "codepipeline_s3_policy" {
  statement {
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetBucketVersioning",
      "s3:PutObject",
      "s3:PutObjectAcl"
    ]

    resources = [
      aws_s3_bucket.artifact_store.arn,
      "${aws_s3_bucket.artifact_store.arn}/*"
    ]
  }
}

resource "aws_iam_role_policy" "codepipeline_s3_policy" {
  name = "practice-codepipeline-s3-policy"
  role = aws_iam_role.codepipeline_role.id
  policy = data.aws_iam_policy_document.codepipeline_s3_policy.json
}

resource "aws_iam_role_policy" "codepipeline_codebuild_policy" {
  name = "practice-codepipeline-codebuild-policy"
  role = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codebuild:StartBuild",
          "codebuild:BatchGetBuilds",
        ]
        Resource = "${aws_codebuild_project.practice_build.arn}"
      }
    ]
  })
}

resource "aws_iam_role_policy" "codepipeline_passrole_policy" {
  name = "practice-codepipeline-passrole-policy"
  role = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole",
        ]
        Resource = aws_iam_role.ecs_execution_role.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "codebuild_loggroup_policy" {
  name = "practice-codebuild-loggroup-policy"
  role = aws_iam_role.codebuild_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${local.aws_region}:${local.account_id}:log-group:/aws/codebuild/${aws_codebuild_project.practice_build.name}:log-stream:*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "codebuild_s3_policy" {
  name = "practice-codebuild-s3-policy"
  role = aws_iam_role.codebuild_role.id
  policy = data.aws_iam_policy_document.codepipeline_s3_policy.json
}

resource "aws_iam_role_policy" "codebuild_ecr_policy" {
  name = "practice-codebuild-ecr-policy"
  role = aws_iam_role.codebuild_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeImages",
          "ecr:DescribeRepositories",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:ListImages",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ]
      Resource = "*"
        
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codepipeline_policy" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodePipeline_FullAccess"
}

resource "aws_ecs_cluster" "practice_cluster" {
  name = "practice-cluster"
}

resource "aws_launch_template" "practice_template" {
  name_prefix   = "ECS-Instance-practice-service"
  image_id      = "ami-02fd4e1237c808705"
  instance_type = "t3.small"

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }

    user_data = base64encode(<<-EOF
              #!/bin/bash
              echo "ECS_CLUSTER=${aws_ecs_cluster.practice_cluster.name}" >> /etc/ecs/ecs.config
              EOF
  )


}

resource "aws_autoscaling_group" "practice_autoscaling_group" {
  vpc_zone_identifier = aws_subnet.practice_subnet[*].id
  desired_capacity   = 1
  max_size           = 2
  min_size           = 1
  

  launch_template {
    id      = aws_launch_template.practice_template.id
    version = "$Latest"
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  }

    tag {
    key                 = "Name"
    value               = "ECS-Instance-practice-service"
    propagate_at_launch = true
  }

}


resource "aws_ecs_service" "practice_service" {
  name            = "practice-service"
  cluster         = aws_ecs_cluster.practice_cluster.arn
  task_definition = aws_ecs_task_definition.practice_task.arn
  launch_type     = "EC2"
  desired_count   = 1

  network_configuration {
    subnets         = aws_subnet.practice_subnet[*].id
    security_groups = [aws_security_group.practice_sg.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.practice_tg.arn
    container_name   = "practice-app"
    container_port   = 5000
  }
}

resource "aws_ecs_task_definition" "practice_task" {
  family                   = "practice-task"
  container_definitions    = jsonencode([
    {
      name  = "practice-app"
      image = "${aws_ecr_repository.practice_ecr_repo.repository_url}:latest"
      portMappings = [
        {
          containerPort = 5000
          hostPort      = 5000
        }
      ]
    }
  ])
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  memory = 256
}

data aws_iam_policy_document ecs_execution_assume_role_policy {
  statement {
    actions = ["sts:AssumeRole"]
 
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

  }

}
resource "aws_iam_role" "ecs_execution_role" {
  name = "practice-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_execution_assume_role_policy.json
}

resource "aws_iam_role_policy" "ecs_execution_role_ecs_policy" {
  role = aws_iam_role.ecs_execution_role.id
  policy = data.aws_iam_policy_document.codepipeline_ecs_policy.json
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_security_group" "practice_sg" {
  name        = "practice-sg"
  description = "Allow inbound traffic for Flask app"
  vpc_id      = aws_vpc.practice_vpc.id

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

   ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS for ECS agent"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP for ECS agent"
  }
}

resource "aws_vpc" "practice_vpc" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_internet_gateway" "practice_igw" {
  vpc_id = aws_vpc.practice_vpc.id

  tags = {
    Name = "practice-igw"
  }
}

resource "aws_route_table" "practice_rt" {
  vpc_id = aws_vpc.practice_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.practice_igw.id
  }

  tags = {
    Name = "practice-rt"
  }
}

resource "aws_route_table_association" "practice_rta" {
  count = 2
  subnet_id      = aws_subnet.practice_subnet[count.index].id
  route_table_id = aws_route_table.practice_rt.id
}

resource "aws_subnet" "practice_subnet" {
  count = 2
  vpc_id     = aws_vpc.practice_vpc.id
  cidr_block = "10.0.${count.index}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_iam_policy" "codepipeline_codestar_policy" {
  name        = "CodePipelineCodeStarPolicy"
  description = "Policy to allow CodePipeline to use CodeStar connections"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codestar-connections:UseConnection"
        ]
        Resource = aws_codestarconnections_connection.github_connection.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codepipeline_codestar_policy_attachment" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = aws_iam_policy.codepipeline_codestar_policy.arn
}

resource "aws_codestarconnections_connection" "github_connection" {
  name          = "github-connection"
  provider_type = "GitHub"
}

resource "aws_iam_role" "ecs_instance_role" {
  name = "practice-ecs-instance-role"
  path = "/"
  assume_role_policy = "${data.aws_iam_policy_document.ecs_instance_policy.json}"
}

data "aws_iam_policy_document" "ecs_instance_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecs_instance_role_attachment" {
  role = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "practice-ecs-instance-profile"
  path = "/"
  role = aws_iam_role.ecs_instance_role.id
}

resource "aws_lb" "practice_alb" {
  name               = "practice-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.practice_sg.id]
  subnets            = aws_subnet.practice_subnet[*].id
}

resource "aws_lb_listener" "practice_listener" {
  load_balancer_arn = aws_lb.practice_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.practice_tg.arn
  }
}

resource "aws_lb_target_group" "practice_tg" {
  name        = "practice-tg"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.practice_vpc.id
  target_type = "ip"

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 10
    timeout             = 60
    interval            = 300
    matcher             = "200,301,302"
  }
}
