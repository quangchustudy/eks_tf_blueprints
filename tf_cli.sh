#check terraform state (of eks-blue folder) -> check detail of each element of the list
## check the terraform state
terraform state list
## check detail of each element
terraform state show module.eks_cluster.data.aws_vpc.vpc

