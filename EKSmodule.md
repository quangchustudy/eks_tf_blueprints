# EKS MODULE

## 1. Create module folder
```bash
mkdir -p ./environment/eks-blueprint/modules/eks_cluster

```

## 2. Create terraform project (versions.tf)
```bash
cat > ./environment/eks-blueprint/modules/eks_cluster/versions.tf << 'EOF'
terraform {
  required_version = ">= 1.4.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}
EOF

```

## 2. Define module's variables (variables.tf)
Here we define a lot of variables that will be used by the solution. Let's define some of them:

- **environment _name** refer to the environment we previously created.
- **service_name** will refer to instances of our module (our EKS cluster names).
- **eks_admin_role_name** is an additional IAM role that will be admin in the cluster.

```bash
cat > ./environment/eks-blueprint/modules/eks_cluster/variables.tf << 'EOF'
variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-southeast-1"
}
variable "environment_name" {
  description = "The name of Environment Infrastructure stack, feel free to rename it. Used for cluster and VPC names."
  type        = string
  default     = "eks-blueprint"
}

variable "service_name" {
  description = "The name of the Suffix for the stack name"
  type        = string
  default     = "blue"
}

variable "cluster_version" {
  description = "The Version of Kubernetes to deploy"
  type        = string
  default     = "1.25"
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

## 3. Define local (locals.tf)
We start by defining some locals:

```bash
cat <<'EOF' > ./environment/eks-blueprint/modules/eks_cluster/locals.tf
locals {
  environment = var.environment_name
  service     = var.service_name

  env  = local.environment
  name = "${local.environment}-${local.service}"

  # Mapping
  cluster_version            = var.cluster_version
  argocd_secret_manager_name = var.argocd_secret_manager_name_suffix
  eks_admin_role_name        = var.eks_admin_role_name

  tag_val_vpc            = local.environment
  tag_val_public_subnet  = "${local.environment}-public-"
  tag_val_private_subnet = "${local.environment}-private-"

  node_group_name = "managed-ondemand"

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }

}

EOF

```

## 3. Our main.tf module file (main.tf)

```bash
cat <<'EOF' > ./environment/eks-blueprint/modules/eks_cluster/main.tf
# Required for public ECR where Karpenter artifacts are hosted
provider "aws" {
  region = "ap-southeast-1"
  alias  = "singapore"
}

EOF

```

## 3.1. Importing some data
- Our existing partition.
- Our AWS identity.
- The VPC we created in our environment.
- The private subnets of our VPC.

```bash
cat <<'EOF' >> ./environment/eks-blueprint/modules/eks_cluster/main.tf
data "aws_partition" "current" {}

# Find the user currently in use by AWS
data "aws_caller_identity" "current" {}

data "aws_vpc" "vpc" {
  filter {
    name   = "tag:Name"
    values = [local.tag_val_vpc]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "tag:Name"
    values = ["${local.tag_val_private_subnet}*"]
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "tag:Name"
    values = ["${local.tag_val_public_subnet}*"]
  }
}

EOF

```

Now we tag the subnets with the name of our EKS cluster, which is the concatenation of the two locals: local.environment and local.service, This will be used by our Load Balancer or Karpenter to know in which subnet our cluster is.

```bash
cat <<'EOF' >> ./environment/eks-blueprint/modules/eks_cluster/main.tf
#Add Tags for the new cluster in the VPC Subnets
resource "aws_ec2_tag" "private_subnets" {
  for_each    = toset(data.aws_subnets.private.ids)
  resource_id = each.value
  key         = "kubernetes.io/cluster/${local.environment}-${local.service}"
  value       = "shared"
}


#Add Tags for the new cluster in the VPC Subnets
resource "aws_ec2_tag" "public_subnets" {
  for_each    = toset(data.aws_subnets.public.ids)
  resource_id = each.value
  key         = "kubernetes.io/cluster/${local.environment}-${local.service}"
  value       = "shared"
}
EOF

```

Finally, we import our secrets for ArgoCD from AWS Secret Manager:

```bash
cat <<'EOF' >> ./environment/eks-blueprint/modules/eks_cluster/main.tf
data "aws_secretsmanager_secret" "argocd" {
  name = "${local.argocd_secret_manager_name}.${local.environment}"
}

data "aws_secretsmanager_secret_version" "admin_password_version" {
  secret_id = data.aws_secretsmanager_secret.argocd.id
}
EOF

```


## 4. Create the EKS cluster
In this step, we are going to add the EKS core module and configure it, including the EKS managed node group. From the code below, you can see that we are pinning the main terraform-aws-modules/eks to version 19.15.1  which corresponds to the GitHub repository release tag. It is a good practice to lock-in all your modules to a given, tried-and-tested version.

```bash
cat <<'EOF' >> ./environment/eks-blueprint/modules/eks_cluster/main.tf
#tfsec:ignore:aws-eks-enable-control-plane-logging
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.15.2"

  cluster_name                   = local.name
  cluster_version                = local.cluster_version
  cluster_endpoint_public_access = true

  vpc_id     = data.aws_vpc.vpc.id
  subnet_ids = data.aws_subnets.private.ids

  #we uses only 1 security group to allow connection with Fargate, MNG, and Karpenter nodes
  create_node_security_group = false
  eks_managed_node_groups = {
    initial = {
      node_group_name = local.node_group_name
      instance_types  = ["m5.large"]

      min_size     = 1
      max_size     = 5
      desired_size = 3
      subnet_ids   = data.aws_subnets.private.ids
    }
  }

  manage_aws_auth_configmap = true
  aws_auth_roles = flatten([
    #module.eks_blueprints_platform_teams.aws_auth_configmap_role,
    #[for team in module.eks_blueprints_dev_teams : team.aws_auth_configmap_role],
    #{
    #  rolearn  = module.karpenter.role_arn
    #  username = "system:node:{{EC2PrivateDNSName}}"
    #  groups = [
    #    "system:bootstrappers",
    #    "system:nodes",
    #  ]
    #},
    {
      rolearn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.eks_admin_role_name}" # The ARN of the IAM role
      username = "ops-role"                                                                                      # The user name within Kubernetes to map to the IAM role
      groups   = ["system:masters"]                                                                              # A list of groups within Kubernetes to which the role is mapped; Checkout K8s Role and Rolebindings
    }
  ])

  tags = merge(local.tags, {
    # NOTE - if creating multiple security groups with this module, only tag the
    # security group that Karpenter should utilize with the following tag
    # (i.e. - at most, only one security group should have this tag in your account)
    "karpenter.sh/discovery" = "${local.environment}-${local.service}"
  })
}

EOF

```

## 5. Get module outputs
We want our module to output some variables we could reuse later:

- The EKS cluster ID
- The command to configure our kubectl for the creator of the EKS cluster

```bash
cat <<'EOF' > ./environment/eks-blueprint/modules/eks_cluster/outputs.tf
output "eks_cluster_id" {
  description = "The name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${var.aws_region} update-kubeconfig --name ${module.eks.cluster_name}"
}

output "eks_cluster_endpoint" {
  description = "The endpoint of the EKS cluster."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "cluster_certificate_authority_data"
  value       = module.eks.cluster_certificate_authority_data
}

EOF

```