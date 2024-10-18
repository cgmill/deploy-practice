# Basic Terraform Project
I created this project to learn how to use terraform and familiarize myself with a CI/CD pipeline. Currently, main.tf is used to set up a load balancer that directs incoming HTTP traffic to an ECS cluster. Below are the steps to deploy the project.


# Usage
To deploy the terraform project, run the following commands:
```
terraform init
terraform apply
```

After deployment, log into your AWS console, navigate to CodePipeline, and update the connection to your GitHub repository.

To destroy the project, run the following command:
```
terraform destroy
```

# TODO
- Move hardcoded values to variables.tf file
    - GitHub repository
- ~ Break up main.tf into multiple files ~ 
- Rename resources
- Review policies for mistakes and principal of least privilege
