output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "Primary CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "secondary_cidr_blocks" {
  description = "Secondary CIDR blocks of the VPC"
  value       = module.vpc.vpc_secondary_cidr_blocks
}

output "private_subnets" {
  description = "All private subnet IDs (primary + secondary CIDRs)"
  value       = module.vpc.private_subnets
}

output "primary_private_subnets" {
  description = "Private subnet IDs from primary CIDR"
  value       = slice(module.vpc.private_subnets, 0, length(local.primary_private_subnets))
}

output "secondary_private_subnets" {
  description = "Private subnet IDs from secondary CIDRs"
  value       = local.secondary_subnet_ids
}

output "public_subnets" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnets
}

output "private_route_table_ids" {
  description = "Private route table IDs"
  value       = module.vpc.private_route_table_ids
}

output "nat_public_ips" {
  description = "NAT gateway public IPs"
  value       = module.vpc.nat_public_ips
}

output "azs" {
  description = "Availability zones used"
  value       = module.vpc.azs
}
