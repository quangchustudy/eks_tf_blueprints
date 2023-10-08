# Add Application Teams
https://catalog.us-east-1.prod.workshops.aws/workshops/d2b662ae-e9d7-4b31-b68b-64ade19d5dcc/en-US/030-provision-eks-cluster/03-team-management/2-add-application-teams

## 1. Add Riker and Burnham Team EKS Tenant
Our next step is to define a Development Team in the EKS Platform as a Tenant. To do that, we add the following section to the main.tf

Under the platform team definition we add the following: If you have specific AWS IAM Roles you would like to add to the team definition, you can do so in the users array, which expects the IAM Role ARN.

Quotas are also enabled, as shown below. Deploying resources without CPU or Memory limits will fail.
Add code below after the platform_teams we just added in the eks_blueprints module.

We can create every team in a separate module, as we did with the platform-team, or we can declare multiple teams in one module using the for_each syntax, as in the below example:

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

This block of code allows us to configure for each team its namespace name, labels, namespace quotas, users, or AWS IAM roles that have access to this specific namespace, and also apply specific Kubernetes manifests as for resource quotas and limit-range. For simplicity, we will pass the current user to the team object (line 24).

As we did previously, this will create 2 teams and kubernetes namespaces, team-burnham and team-riker, with service accounts preconfigured with the IAM role, resource quotas, and limit-range pre-created.

The created roles will be similar to:

arn:aws:iam::0123456789:role/team-riker-XXXXXXXXXX
arn:aws:iam::0123456789:role/team-burnham-XXXXXXXXXX
Apply the changes:

```bash
cd ./environment/eks-blueprint/eks-blue
terraform init
terraform apply -auto-approve

```

You can use kubectl to check the created objects:

```bash
#list new namespaces
kubectl get ns

#list resources quotas in all namespaces
kubectl get resourcequota -A

#list limit-range in all namespaces
kubectl get limitrange -A

#check the team-riker service account
kubectl describe sa -n team-riker team-riker

```

Important
If you need to add other teams, you can just expand the for_each in line 6 or create another module instance.

### 3. Configure authentication for the team in the clusterHeader anchor link
Our philosophy with multi-tenant access for teams in a cluster, is to rely on GitOps  principles to manage writing in a cluster. The idea is to have a dedicated git repository for each team configured in their own namespace; we will discuss it in detail later.

This means that by default, we will provide teams in their namespace with only read-only cluster access. This way, they can use kubectl to view what is deployed in the cluster but cannot make modifications outside of their GitOps workflow.

Let's add our team role to the allowed list to authenticate in the EKS cluster. Open again the eks_cluster/main.tf file:

```bash
c9 open ./environment/eks-blueprint/modules/eks_cluster/main.tf

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

Apply change
```bash
# We need to do this again since we added a new module.
cd ./environment/eks-blueprint/eks-blue
# It is always a good practice to use a dry-run command
terraform plan
# Then provision our EKS cluster
# The auto approve flag avoids you having to confirm you want to provision resources.
terraform apply -auto-approve
```

This will allow you to use the AWS Roles created for our platform-team, team-riker and team-burnham in EKS. You can see this by looking at the configuration in the aws-auth ConfigMap.

```bash
kubectl get cm aws-auth -n kube-system -o yaml

```

### 4. update output.tf of eks module
Now that our team roles are allowed to connect to the EKS cluster, let's add them to the Terraform Outputs so that it will be easier to use them.

Execute this command to add the Outputs to the Terraform. We need to add them both in the module and in our stack:

#### 4.1.Update the module
```bash
cat <<'EOF' >> ./environment/eks-blueprint/modules/eks_cluster/outputs.tf

output "eks_blueprints_platform_teams_configure_kubectl" {
  description = "Configure kubectl for Platform Team: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${var.aws_region} update-kubeconfig --name ${module.eks.cluster_name}  --role-arn ${module.eks_blueprints_platform_teams.iam_role_arn}"
}

output "eks_blueprints_dev_teams_configure_kubectl" {
  description = "Configure kubectl for each Dev Application Teams: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = [for team in module.eks_blueprints_dev_teams : "aws eks --region ${var.aws_region} update-kubeconfig --name ${module.eks.cluster_name}  --role-arn ${team.iam_role_arn}"]
}

EOF

```

#### 2. Update the stack
cat <<'EOF' >> ./environment/eks-blueprint/eks-blue/outputs.tf

output "eks_blueprints_platform_teams_configure_kubectl" {
  description = "Configure kubectl for Platform Team: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = module.eks_cluster.eks_blueprints_platform_teams_configure_kubectl
}

output "eks_blueprints_dev_teams_configure_kubectl" {
  description = "Configure kubectl for each Dev Application Teams: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = module.eks_cluster.eks_blueprints_dev_teams_configure_kubectl
}

EOF

#### 6. Apply changes
```bash
# We need to do this again since we added a new module.
cd ./environment/eks-blueprint/eks-blue
# It is always a good practice to use a dry-run command
terraform plan
# then provision our EKS cluster
# the auto approve flag avoids you having to confirm you want to provision resources.
terraform apply -auto-approve

```