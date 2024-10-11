terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  required_version = ">= 1.2.0"
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
      value = "practice-container"
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
        ConnectionArn = "arn:aws:codestar-connections:us-east-2:515966492950:connection/3fd7218d-19b7-4136-bb84-73ca2459a857"
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
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        ClusterName = aws_ecs_cluster.practice_cluster.name
        ServiceName = aws_ecs_service.practice_service.name
        FileName    = "imagedefinitions.json"
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

resource "aws_iam_role_policy_attachment" "codepipeline_policy" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodePipeline_FullAccess"
}










resource "aws_ecs_cluster" "practice_cluster" {
  name = "practice-cluster"
}

resource "aws_ecs_service" "practice_service" {
  name            = "practice-service"
  cluster         = aws_ecs_cluster.practice_cluster.id
  task_definition = aws_ecs_task_definition.practice_task.arn
  launch_type     = "EC2"
  desired_count   = 1

  network_configuration {
    subnets         = [aws_subnet.practice_subnet.id]
    security_groups = [aws_security_group.practice_sg.id]
  }
}

resource "aws_ecs_task_definition" "practice_task" {
  family                   = "practice-task"
  container_definitions    = jsonencode([
    {
      name  = "practice-container"
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
  memory                   = 512
  cpu                      = 256
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
}

resource "aws_iam_role" "ecs_execution_role" {
  name = "practice-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
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
}

resource "aws_vpc" "practice_vpc" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "practice_subnet" {
  vpc_id     = aws_vpc.practice_vpc.id
  cidr_block = "10.0.1.0/24"
}

