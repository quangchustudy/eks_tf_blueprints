# Provision Amazon eks blue cluster
```bash
mkdir -p ./environment/eks-blueprint/eks-blue
```

## 1. Let's create the Terraform structure for our EKS blue cluste
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

## 2. 2. Let's create the variables for our clusterHeader anchor link
```bash
cat > ./environment/eks-blueprint/eks-blue/variables.tf << 'EOF'
variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-southeast-1"
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

## 3. And link to our terraform.tfvars variable fileHeader anchor link
```bash
ln -s ./environment/eks-blueprint/terraform.tfvars ./environment/eks-blueprint/eks-blue/terraform.tfvars

```

## 4. 4. Create our main.tf fileHeader anchor link
We configure our providers for kubernetes, helm and kubectl.
We call our eks-blueprint module, prividing the variables.
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

## 5. Define our Terraform outputs
We want our Terraform stack to output information from our eks_cluster module:

- The EKS cluster ID.
- The command to configure our kubectl for the creator of the EKS cluster.

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

## 6. Execute it
```bash
# we need to do this again, since we added a new module.
cd ./environment/eks-blueprint/eks-blue
terraform init
# Always a good practice to use a dry-run command
terraform plan
# then provision our EKS cluster
# the auto approve flag avoids you having to confirm you want to provision resources.
terraform apply -auto-approve

```

## 7. Check it
terraform output
```bash
terraform output
```

```output
#output
configure_kubectl = "aws eks --region ap-southeast-1 update-kubeconfig --name eks-blueprint-blue"
```

connect to EKS cluster 
```bash
aws eks --region ap-southeast-1 update-kubeconfig --name eks-blueprint-blue
```

list ns and list pods
```bash
kubectl get ns
kubectl get pods -A
```

At this stage, we just installed a basic EKS cluster with the minimal addon required to work:

- VPC CNI driver, so we get AWS VPC support for our pods.
- CoreDNS for internal Domain Name resolution.
- Kube-proxy to allow the usage of Kubernetes services.
This is not sufficient to work in AWS; we are going to see how we can improve our deployments in the next sections.

