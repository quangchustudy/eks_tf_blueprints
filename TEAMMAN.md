## ADD PLATFORM TEAM
### 1. Add platform team
```bash
cat <<'EOF' >> ./environment/eks-blueprint/modules/eks_cluster/main.tf

data "aws_iam_role" "eks_admin_role_name" {
  count     = local.eks_admin_role_name != "" ? 1 : 0
  name = local.eks_admin_role_name
}

module "eks_blueprints_platform_teams" {
  source  = "aws-ia/eks-blueprints-teams/aws"
  version = "~> 0.2"

  name = "team-platform"

  # Enables elevated, admin privileges for this team
  enable_admin = true
 
  # Define who can impersonate the team-platform Role
  users             = [
    data.aws_caller_identity.current.arn,
    try(data.aws_iam_role.eks_admin_role_name[0].arn, data.aws_caller_identity.current.arn),
  ]
  cluster_arn       = module.eks.cluster_arn
  oidc_provider_arn = module.eks.oidc_provider_arn

  labels = {
    "elbv2.k8s.aws/pod-readiness-gate-inject" = "enabled",
    "appName"                                 = "platform-team-app",
    "projectName"                             = "project-platform",
  }

  annotations = {
    team = "platform"
  }

  namespaces = {
    "team-platform" = {

      resource_quota = {
        hard = {
          "requests.cpu"    = "10000m",
          "requests.memory" = "20Gi",
          "limits.cpu"      = "20000m",
          "limits.memory"   = "50Gi",
          "pods"            = "20",
          "secrets"         = "20",
          "services"        = "20"
        }
      }

      limit_range = {
        limit = [
          {
            type = "Pod"
            max = {
              cpu    = "1000m"
              memory = "1Gi"
            },
            min = {
              cpu    = "10m"
              memory = "4Mi"
            }
          },
          {
            type = "PersistentVolumeClaim"
            min = {
              storage = "24M"
            }
          }
        ]
      }
    }

  }

  tags = local.tags
}
EOF

```

```bash
# We need to do this again since we added a new module.
cd ./environment/eks-blueprint/eks-blue
terraform init

```

```bash
# It is always a good practice to use a dry-run command
terraform plan

```

```bash
# then provision our EKS cluster
# the auto approve flag avoids you having to confirm you want to provision resources.
terraform apply -auto-approve

```

```bash
kubectl get ns

```

```bash
kubectl describe resourcequotas -n team-platform

```

```bash
kubectl describe limitrange -n team-platform

```

```bash
kubectl describe sa -n team-platform team-platform

```

```bash
kubectl get sa -A
```

```bash
kubectl get sa -n team-platform
```

```bash
terraform state list module.eks_cluster.module.eks_blueprints_platform_teams

```

And I think it would be better if we can have a meeting to share more details on your each use case and from there, aws team can understand more and give more feedbacks on it.

## ADD APPLICATION TEAMS

```bash
cat <<'EOF' >> ./environment/eks-blueprint/modules/eks_cluster/main.tf
module "eks_blueprints_dev_teams" {
  source  = "aws-ia/eks-blueprints-teams/aws"
  version = "~> 0.2"

  for_each = {
    burnham = {
      labels = {
        "elbv2.k8s.aws/pod-readiness-gate-inject" = "enabled",
        "appName"                                 = "burnham-team-app",
        "projectName"                             = "project-burnham",
      }
    }
    riker = {
      labels = {
        "elbv2.k8s.aws/pod-readiness-gate-inject" = "enabled",
        "appName"                                 = "riker-team-app",
        "projectName"                             = "project-riker",
      }
    }
  }
  name = "team-${each.key}"

  users             = [data.aws_caller_identity.current.arn]
  cluster_arn       = module.eks.cluster_arn
  oidc_provider_arn = module.eks.oidc_provider_arn

  labels = merge(
    {
      team = each.key
    },
    try(each.value.labels, {})
  )

  annotations = {
    team = each.key
  }

  namespaces = {
    "team-${each.key}" = {
      labels = merge(
        {
          team = each.key
        },
        try(each.value.labels, {})
      )

      resource_quota = {
        hard = {
          "requests.cpu"    = "100",
          "requests.memory" = "20Gi",
          "limits.cpu"      = "200",
          "limits.memory"   = "50Gi",
          "pods"            = "15",
          "secrets"         = "10",
          "services"        = "20"
        }
      }

      limit_range = {
        limit = [
          {
            type = "Pod"
            max = {
              cpu    = "2"
              memory = "1Gi"
            }
            min = {
              cpu    = "10m"
              memory = "4Mi"
            }
          },
          {
            type = "PersistentVolumeClaim"
            min = {
              storage = "24M"
            }
          },
          {
            type = "Container"
            default = {
              cpu    = "50m"
              memory = "24Mi"
            }
          }
        ]
      }
    }
  }

  tags = local.tags

}

EOF

```

```bash
cd ~/environment/eks-blueprint/eks-blue
terraform init
terraform apply -auto-approve

```

### Configure authentication for the team in the cluster

```bash
c9 open ~/environment/eks-blueprint/modules/eks_cluster/main.tf

```
Find and uncomment the following section (lines 2 and 3 below):
```bash
  aws_auth_roles = flatten([
    module.eks_blueprints_platform_teams.aws_auth_configmap_role,                  # <-- Uncomment
    [for team in module.eks_blueprints_dev_teams : team.aws_auth_configmap_role],  # <-- Uncomment
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

```