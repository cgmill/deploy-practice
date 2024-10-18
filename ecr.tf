# Create ECR Repository
resource "aws_ecr_repository" "this" {
  name                 = "flask-repo"
  image_tag_mutability = "MUTABLE"
}

output "repository_url" {
  description = "URL for container repository"
  value       = aws_ecr_repository.this.repository_url
}