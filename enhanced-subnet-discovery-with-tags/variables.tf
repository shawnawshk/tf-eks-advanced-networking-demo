variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name prefix for resources"
  type        = string
  default     = "enhanced-networking"
}

variable "vpc_cidr" {
  description = "Primary VPC CIDR block"
  type        = string
  default     = "10.8.0.0/16"
}

variable "eks_unsupported_az_ids" {
  description = "AZ IDs to exclude (e.g. use1-az3 does not support EKS in us-east-1)"
  type        = list(string)
  default     = ["use1-az3"]
}

variable "secondary_cidrs" {
  description = "Secondary CIDR blocks for the VPC"
  type        = list(string)
  default     = ["10.1.0.0/16", "10.2.0.0/16", "10.3.0.0/16"]
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
