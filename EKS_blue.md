```bash
cat > ./environment/eks-blueprint/eks-blue/providers.tf << 'EOF'
terraform {
  required_version = ">= 1.4.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.20.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.9.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14"
    }
  }
}

EOF

```

```bash
cat > ./environment/eks-blueprint/eks-blue/variables.tf << 'EOF'
variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-west-2"
}

variable "environment_name" {
  description = "The name of Environment Infrastructure stack name, feel free to rename it. Used for cluster and VPC names."
  type        = string
  default     = "eks-blueprint"
}

variable "eks_admin_role_name" {
  type        = string
  description = "Additional IAM role to be admin in the cluster"
  default     = ""
}

variable "argocd_secret_manager_name_suffix" {
  type        = string
  description = "Name of secret manager secret for ArgoCD Admin UI Password"
  default     = "argocd-admin-secret"
}

EOF

```

```bash
cd ./environment/eks-blueprint/eks-blue
ln -s ../../eks-blueprint/terraform.tfvars terraform.tfvars

```

```bash
cat > ./environment/eks-blueprint/eks-blue/main.tf << 'EOF'
provider "aws" {
  region = var.aws_region
}

provider "kubernetes" {
  host                   = module.eks_cluster.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_cluster.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = ["eks", "get-token", "--cluster-name", module.eks_cluster.eks_cluster_id]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks_cluster.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_cluster.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = ["eks", "get-token", "--cluster-name", module.eks_cluster.eks_cluster_id]
    }
  }
}

provider "kubectl" {
  apply_retry_count      = 10
  host                   = module.eks_cluster.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_cluster.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = ["eks", "get-token", "--cluster-name", module.eks_cluster.eks_cluster_id]
  }
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks_cluster.eks_cluster_id
}

module "eks_cluster" {
  source = "../modules/eks_cluster"

  aws_region      = var.aws_region
  service_name    = "blue"
  cluster_version = "1.25"

  environment_name       = var.environment_name
  eks_admin_role_name    = var.eks_admin_role_name

  argocd_secret_manager_name_suffix = var.argocd_secret_manager_name_suffix

  #addons_repo_url = var.addons_repo_url 

  #workload_repo_url      = var.workload_repo_url
  #workload_repo_revision = var.workload_repo_revision
  #workload_repo_path     = var.workload_repo_path

}

EOF

```

```bash
cat > ./environment/eks-blueprint/eks-blue/outputs.tf << 'EOF'
output "eks_cluster_id" {
  description = "The name of the EKS cluster."
  value       = module.eks_cluster.eks_cluster_id
}

output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = module.eks_cluster.configure_kubectl
}
EOF

```