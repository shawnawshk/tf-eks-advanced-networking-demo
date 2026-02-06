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
  description = "Private subnet IDs (primary CIDR)"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnets
}

output "intra_subnets" {
  description = "Intra subnet IDs (secondary CIDRs)"
  value       = module.vpc.intra_subnets
}

output "intra_subnet_cidrs" {
  description = "Intra subnet CIDR blocks"
  value       = module.vpc.intra_subnets_cidr_blocks
}

output "private_route_table_ids" {
  description = "Private route table IDs"
  value       = module.vpc.private_route_table_ids
}

output "intra_route_table_ids" {
  description = "Intra route table IDs"
  value       = module.vpc.intra_route_table_ids
}

output "nat_public_ips" {
  description = "NAT gateway public IPs"
  value       = module.vpc.nat_public_ips
}

output "azs" {
  description = "Availability zones used"
  value       = module.vpc.azs
}
