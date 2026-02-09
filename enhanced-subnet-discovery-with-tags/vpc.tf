
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = var.name
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  secondary_cidr_blocks = var.secondary_cidrs

  enable_nat_gateway     = true
  one_nat_gateway_per_az = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}

# Tag secondary CIDR subnets for VPC CNI subnet discovery and Karpenter
resource "aws_ec2_tag" "secondary_cni" {
  count       = length(local.secondary_subnet_ids)
  resource_id = local.secondary_subnet_ids[count.index]
  key         = "kubernetes.io/role/cni"
  value       = "1"
}

resource "aws_ec2_tag" "secondary_karpenter" {
  count       = length(local.secondary_subnet_ids)
  resource_id = local.secondary_subnet_ids[count.index]
  key         = "karpenter.sh/discovery"
  value       = local.name
}
