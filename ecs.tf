resource "aws_ecs_cluster" "this" {
  name = "flask-cluster"
}

resource "aws_ecs_service" "this" {
  name            = "flask-service"
  cluster         = aws_ecs_cluster.this.arn
  task_definition = aws_ecs_task_definition.this.arn
  launch_type     = "EC2"
  desired_count   = 1

  network_configuration {
    subnets         = aws_subnet.this[*].id
    security_groups = [aws_security_group.this.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = "flask-app"
    container_port   = 5000
  }
}

resource "aws_autoscaling_group" "this" {
  vpc_zone_identifier = aws_subnet.this[*].id
  desired_capacity   = 1
  max_size           = 2
  min_size           = 1
  

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  }

    tag {
    key                 = "Name"
    value               = "ECS-Instance-flask-service"
    propagate_at_launch = true
  }

}



