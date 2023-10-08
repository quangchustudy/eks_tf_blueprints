output "eks_vpc_id" {
  description = "The ID of the VPC"
  value       = module.eks_vpc.eks_vpc_id
}

output "argocd_pwd" {
  description = "ArgoCD password"
  value = module.eks_sm.argocd_pwd
  sensitive = true
}

