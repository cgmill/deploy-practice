resource "aws_launch_template" "this" {
  name_prefix   = "ECS-Instance-flask-service"
  image_id      = "ami-02fd4e1237c808705"
  instance_type = "t3.small"

  iam_instance_profile {
    name = aws_iam_instance_profile.this.name
  }

    user_data = base64encode(<<-EOF
              #!/bin/bash
              echo "ECS_CLUSTER=${aws_ecs_cluster.this.name}" >> /etc/ecs/ecs.config
              EOF
  )
}

resource "aws_iam_instance_profile" "this" {
  name = "ecs-instance-profile"
  path = "/"
  role = aws_iam_role.ecs_instance_role.id
}


resource "aws_iam_role_policy_attachment" "ecs_instance_role_attachment" {
  role = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role" "ecs_instance_role" {
  name = "ecs-instance-role"
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