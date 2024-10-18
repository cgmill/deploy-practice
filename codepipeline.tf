resource "aws_codepipeline" "this" {
  name     = "flask-docker-pipeline"
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
        ConnectionArn = aws_codestarconnections_connection.github.arn
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
        ProjectName = aws_codebuild_project.this.name
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
        ClusterName = aws_ecs_cluster.this.name
        ServiceName = aws_ecs_service.this.name
        FileName    = "imagedefinitions.json"
        DeploymentTimeout = "10" # Might just be DeploymentTimeout
      }
    }
  }
}

# IAM role for CodePipeline
resource "aws_iam_role" "codepipeline_role" {
  name = "flask-codepipeline-role"

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
  name = "codepipeline-ecs-policy"
  role = aws_iam_role.codepipeline_role.id
  policy = data.aws_iam_policy_document.codepipeline_ecs_policy.json
}


data "aws_iam_policy_document" "artifact_store_access" {
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

resource "aws_iam_role_policy" "artifact_store_access" {
  name = "codepipeline-s3-policy"
  role = aws_iam_role.codepipeline_role.id
  policy = data.aws_iam_policy_document.artifact_store_access.json
}

resource "aws_iam_role_policy" "codepipeline_passrole_policy" {
  name = "codepipeline-passrole-policy"
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

resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs-execution-role"
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

data aws_iam_policy_document ecs_execution_assume_role_policy {
  statement {
    actions = ["sts:AssumeRole"]
 
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

  }

}


resource "aws_iam_role_policy" "codepipeline_codebuild_policy" {
  name = "codepipeline-codebuild-policy"
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
        Resource = "${aws_codebuild_project.this.arn}"
      }
    ]
  })
}

resource "aws_codestarconnections_connection" "github" {
  name          = "github-connection"
  provider_type = "GitHub"
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
        Resource = aws_codestarconnections_connection.github.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codepipeline_codestar_policy_attachment" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = aws_iam_policy.codepipeline_codestar_policy.arn
}
