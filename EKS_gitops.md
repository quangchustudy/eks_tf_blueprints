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
  #addons_repo_url            = var.addons_repo_url  
  #workload_repo_path         = var.workload_repo_path
  #workload_repo_url          = var.workload_repo_url
  #workload_repo_revision     = var.workload_repo_revision

  tag_val_vpc            = local.environment
  tag_val_public_subnet  = "${local.environment}-public-"
  tag_val_private_subnet = "${local.environment}-private-"

  node_group_name = "managed-ondemand"

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }
  
  #---------------------------------------------------------------
  # ARGOCD ADD-ON APPLICATION
  #---------------------------------------------------------------

  #At this time (with new v5 addon repository), the Addons need to be managed by Terrform and not ArgoCD
  addons_application = {
    path                = "chart"
    repo_url            = local.addons_repo_url
    add_on_application  = true
  }

  #---------------------------------------------------------------
  # ARGOCD WORKLOAD APPLICATION
  #---------------------------------------------------------------

  workload_application = {
    path                = local.workload_repo_path # <-- we could also to blue/green on the workload repo path like: envs/dev-blue / envs/dev-green
    repo_url            = local.workload_repo_url
    target_revision     = local.workload_repo_revision

    add_on_application  = false
    
    values = {
      labels = {
        env   = local.env
      }
      spec = {
        source = {
          repoURL        = local.workload_repo_url
          targetRevision = local.workload_repo_revision
        }
        blueprint                = "terraform"
        clusterName              = local.name
        #karpenterInstanceProfile = module.karpenter.instance_profile_name # Activate to enable Karpenter manifests (only when Karpenter add-on will be enabled in the Karpenter workshop)
        env                      = local.env
      }
    }
  }  

}

EOF

```

```bash
cat <<'EOF' >> ./environment/eks-blueprint/modules/eks_cluster/variables.tf
variable "workload_repo_url" {
  type        = string
  description = "Git repo URL for the ArgoCD workload deployment"
  default     = "https://github.com/aws-samples/eks-blueprints-workloads.git"
}

variable "workload_repo_revision" {
  type        = string
  description = "Git repo revision in workload_repo_url for the ArgoCD workload deployment"
  default     = "main"
}

variable "workload_repo_path" {
  type        = string
  description = "Git repo path in workload_repo_url for the ArgoCD workload deployment"
  default     = "envs/dev"
}

variable "addons_repo_url" {
  type        = string
  description = "Git repo URL for the ArgoCD addons deployment"
  default     = "https://github.com/aws-samples/eks-blueprints-add-ons.git"
}

EOF

```

```bash
cat <<'EOF' >> ./environment/eks-blueprint/eks-blue/variables.tf
variable "workload_repo_url" {
  type        = string
  description = "Git repo URL for the ArgoCD workload deployment"
  default     = "https://github.com/aws-samples/eks-blueprints-workloads.git"
}

variable "workload_repo_secret" {
  type        = string
  description = "Secret Manager secret name for hosting Github SSH-Key to Access private repository"
  default     = "github-blueprint-ssh-key"
}

variable "workload_repo_revision" {
  type        = string
  description = "Git repo revision in workload_repo_url for the ArgoCD workload deployment"
  default     = "main"
}

variable "workload_repo_path" {
  type        = string
  description = "Git repo path in workload_repo_url for the ArgoCD workload deployment"
  default     = "envs/dev"
}

variable "addons_repo_url" {
  type        = string
  description = "Git repo URL for the ArgoCD addons deployment"
  default     = "https://github.com/aws-samples/eks-blueprints-add-ons.git"
}

EOF

```

```bash
cat >>  ./environment/eks-blueprint/terraform.tfvars <<EOF
addons_repo_url = "https://github.com/aws-samples/eks-blueprints-add-ons.git"

workload_repo_url = "https://github.com/${GITHUB_USER}/eks-blueprints-workloads.git"
workload_repo_revision = "main"
workload_repo_path     = "envs/dev"
EOF

```

```bash
cat <<'EOF' >> ./environment/eks-blueprint/modules/eks_cluster/main.tf
module "kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints?ref=blueprints-workshops/modules/kubernetes-addons"

  eks_cluster_id     = module.eks.cluster_name

  #---------------------------------------------------------------
  # ARGO CD ADD-ON
  #---------------------------------------------------------------

  enable_argocd         = true
  argocd_manage_add_ons = true # Indicates that ArgoCD is responsible for managing/deploying Add-ons.

  argocd_applications = {
    addons    = local.addons_application
    #workloads = local.workload_application #We comment it for now
  }

  argocd_helm_config = {
    set_sensitive = [
      {
        name  = "configs.secret.argocdServerAdminPassword"
        value = bcrypt(data.aws_secretsmanager_secret_version.admin_password_version.secret_string)
      }
    ]    
    set = [
      {
        name  = "server.service.type"
        value = "LoadBalancer"
      }
    ]
  }

  #---------------------------------------------------------------
  # EKS Managed AddOns
  # https://aws-ia.github.io/terraform-aws-eks-blueprints/add-ons/
  #---------------------------------------------------------------

  enable_amazon_eks_coredns = true
  enable_amazon_eks_kube_proxy = true
  enable_amazon_eks_vpc_cni = true      
  enable_amazon_eks_aws_ebs_csi_driver = true

  #---------------------------------------------------------------
  # ADD-ONS - You can add additional addons here
  # https://aws-ia.github.io/terraform-aws-eks-blueprints/add-ons/
  #---------------------------------------------------------------


  enable_aws_load_balancer_controller  = true
  enable_aws_for_fluentbit             = true
  enable_metrics_server                = true

}
EOF

```