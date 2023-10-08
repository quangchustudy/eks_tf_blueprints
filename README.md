# EKS Blueprints for Terraform

# Configure our environment
## 1. Create our TF project
```bash
mkdir -p ./environment/eks-blueprint/environment
#cd ./environment/eks-blueprint/environment
```
First, we create a file called versions.tf that indicates which versions of Terraform and providers our project will use:
```bash
cat > ./environment/eks-blueprint/environment/versions.tf << 'EOF'
terraform {
  required_version = ">= 1.4.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
    random = {
      version = ">= 3"
    }
  }
}
EOF

```

### 2. Define our project's var
Our environment's Terraform stack will have some variables so we can configure it:

1. Environment name.
2. The AWS region to use.
3. The VPC cidr we want to create.
4. A suffix that will be used to create a secret for ArgoCD later.
```bash
cat > ./environment/eks-blueprint/environment/variables.tf << 'EOF'
variable "environment_name" {
  description = "The name of environment Infrastructure stack, feel free to rename it. Used for cluster and VPC names."
  type        = string
  default     = "eks-blueprint"
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-southeast-1"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "argocd_secret_manager_name_suffix" {
  type        = string
  description = "Name of secret manager secret for ArgoCD Admin UI Password"
  default     = "argocd-admin-secret"
}
EOF

```

### 3. Define our project's main file
```bash
cat > ./environment/eks-blueprint/environment/main.tf <<'EOF'
provider "aws" {
  region = local.region
}

data "aws_availability_zones" "available" {}

locals {
  name   = var.environment_name
  region = var.aws_region

  vpc_cidr       = var.vpc_cidr
  num_of_subnets = min(length(data.aws_availability_zones.available.names), 3)
  azs            = slice(data.aws_availability_zones.available.names, 0, local.num_of_subnets)

  argocd_secret_manager_name = var.argocd_secret_manager_name_suffix

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }
}

EOF

```

## Create our VPC
```bash
cat >> ./environment/eks-blueprint/environment/main.tf <<'EOF'
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 6, k)]
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 6, k + 10)]

  enable_nat_gateway   = true
  create_igw           = true
  enable_dns_hostnames = true
  single_nat_gateway   = true

  manage_default_network_acl    = true
  default_network_acl_tags      = { Name = "${local.name}-default" }
  manage_default_route_table    = true
  default_route_table_tags      = { Name = "${local.name}-default" }
  manage_default_security_group = true
  default_security_group_tags   = { Name = "${local.name}-default" }

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags

}

EOF

```

## Create additional resources
```bash
cat >> ./environment/eks-blueprint/environment/main.tf <<'EOF'
#---------------------------------------------------------------
# ArgoCD Admin Password credentials with Secrets Manager
# Login to AWS Secrets manager with the same role as Terraform to extract the ArgoCD admin password with the secret name as "argocd"
#---------------------------------------------------------------
resource "random_password" "argocd" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

#tfsec:ignore:aws-ssm-secret-use-customer-key
resource "aws_secretsmanager_secret" "argocd" {
  name                    = "${local.argocd_secret_manager_name}.${local.name}"
  recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
}

resource "aws_secretsmanager_secret_version" "argocd" {
  secret_id     = aws_secretsmanager_secret.argocd.id
  secret_string = random_password.argocd.result
}

EOF

```

## Create an outputs.tf file
```bash
cat > ./environment/eks-blueprint/environment/outputs.tf <<'EOF'
output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

EOF

```

## Provide variables
```bash
cat >  ./environment/eks-blueprint/terraform.tfvars <<EOF
aws_region          = "ap-southeast-1"
environment_name     = "eks-blueprint"

eks_admin_role_name = "Admin"

EOF

```

Link this file into our environment directory:

```bash
ln -s ./environment/eks-blueprint/terraform.tfvars ./environment/eks-blueprint/environment/terraform.tfvars

```

# CREATE THE ENVIRONMENT
```bash
# Initialize Terraform so that we get all the required modules and providers
cd ./environment/eks-blueprint/environment
terraform init

```

```bash
# It is always a good practice to use a dry-run command
terraform plan

```

```bash
# The auto-approve flag avoids you having to confirm that you want to provision resources.
terraform apply -auto-approve

```# eks_tf_blueprints
# eks_tf_blueprints
# eks_tf_blueprints
