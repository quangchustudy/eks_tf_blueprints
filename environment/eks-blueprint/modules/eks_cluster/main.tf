# Required for public ECR where Karpenter artifacts are hosted
provider "aws" {
  region = "ap-southeast-1"
  alias  = "singapore"
}

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


#Add Tags for the new cluster in the VPC Subnets
resource "aws_ec2_tag" "private_subnets" {
  for_each    = toset(data.aws_subnets.private.ids)
  resource_id = each.value
  key         = "kubernetes.io/cluster/${local.environment}-${local.service}"
  value       = "shared"
}

data "aws_subnets" "public" {
  filter {
    name   = "tag:Name"
    values = ["${local.tag_val_public_subnet}*"]
  }
}

#Add Tags for the new cluster in the VPC Subnets
resource "aws_ec2_tag" "public_subnets" {
  for_each    = toset(data.aws_subnets.public.ids)
  resource_id = each.value
  key         = "kubernetes.io/cluster/${local.environment}-${local.service}"
  value       = "shared"
}
data "aws_secretsmanager_secret" "argocd" {
  name = "${local.argocd_secret_manager_name}.${local.environment}"
}

data "aws_secretsmanager_secret_version" "admin_password_version" {
  secret_id = data.aws_secretsmanager_secret.argocd.id
}
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

