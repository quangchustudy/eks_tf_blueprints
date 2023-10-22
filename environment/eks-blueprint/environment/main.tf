provider "aws" {
  # region = local.region
  region = var.aws_region
  # region = "ap-southeast-1"
}

module "eks_vpc" {
  source = "../modules/eks_vpc"

  aws_region      = var.aws_region
  vpc_cidr        = "10.0.0.0/16"
}

module "eks_sm" {
  source = "../modules/eks_sm"
  
}



