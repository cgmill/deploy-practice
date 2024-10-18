resource "aws_ecs_task_definition" "this" {
  family                   = "flask-task"
  container_definitions    = jsonencode([
    {
      name  = "flask-app"
      image = "${aws_ecr_repository.this.repository_url}:latest"
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
