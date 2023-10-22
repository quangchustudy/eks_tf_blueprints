#delete EKS cluster
cd ~/environment/eks-blueprint/eks-blue
terraform destroy -target="module.eks_cluster.module.eks" -auto-approve

#delete whole stack
terraform destroy -auto-approve

#delete env
cd ~/environment/eks-blueprint/environment
terraform destroy -auto-approve
