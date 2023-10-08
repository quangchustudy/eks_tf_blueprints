locals {
  name                       = var.environment_name
  region                     = var.aws_region
  
  argocd_secret_manager_name = var.argocd_secrret_manager_name_suffix
  tags = {
    Blueprint  = var.environment_name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }
}
