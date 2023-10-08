output "eks_vpc_id" {
  description = "The id of eks vpc"
  value       = module.vpc.vpc_id
}