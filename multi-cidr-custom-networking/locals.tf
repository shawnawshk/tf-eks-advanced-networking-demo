locals {
  # General
  name      = var.name
  namespace = "karpenter"

  tags = merge(var.tags, {
    "karpenter.sh/discovery" = local.name
  })

  # Networking — AZs and subnet CIDRs
  # NOTE: slice(..., 0, 6) assumes us-east-1 (6 AZs). Adapt for other regions.
  azs = slice(data.aws_availability_zones.available.names, 0, 6)

  # Primary CIDR subnets (10.8.0.0/16) - 6x /20
  private_subnets = [for i in range(6) : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i in range(6) : cidrsubnet(var.vpc_cidr, 4, i + 6)]

  # Secondary CIDR subnets - 2 AZs per secondary CIDR, one /17 per AZ
  # 100.64.0.0/16 -> AZ a,b | 100.65.0.0/16 -> AZ c,d | 100.66.0.0/16 -> AZ e,f
  intra_subnets = flatten([
    for cidr in var.secondary_cidrs : [
      cidrsubnet(cidr, 1, 0),
      cidrsubnet(cidr, 1, 1),
    ]
  ])

  # EKS control plane does not support us-east-1e; extend var.eks_excluded_azs for other regions
  eks_private_subnet_ids = [
    for i, subnet in module.vpc.private_subnets : subnet
    if !contains(var.eks_excluded_azs, local.azs[i])
  ]

  # SGs assigned to pod secondary ENIs via ENIConfig.
  # Must mirror every SG attached to nodes - pod traffic bypasses the node's primary ENI.
  # If you add a node-level SG (e.g. for RDS, ElastiCache), add it here too.
  eniconfig_security_group_ids = [
    module.eks.cluster_primary_security_group_id,
  ]
}
