variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name prefix for resources"
  type        = string
  default     = "eks-networking"
}

variable "vpc_cidr" {
  description = "Primary VPC CIDR block"
  type        = string
  default     = "10.8.0.0/16"
}

variable "secondary_cidrs" {
  description = "Secondary CIDR blocks for the VPC"
  type        = list(string)
  default = [
    "100.64.0.0/16", "100.65.0.0/16", "100.66.0.0/16", "100.67.0.0/16",
    "100.68.0.0/16", "100.69.0.0/16", "100.70.0.0/16", "100.71.0.0/16",
    "100.72.0.0/16", "100.73.0.0/16", "100.74.0.0/16", "100.75.0.0/16",
    "100.76.0.0/16", "100.77.0.0/16", "100.78.0.0/16", "100.79.0.0/16",
    "100.80.0.0/16", "100.81.0.0/16", "100.82.0.0/16", "100.83.0.0/16",
  ]
}

variable "eks_unsupported_az_ids" {
  description = "AZ IDs that do not support EKS control plane (e.g. use1-az3 for us-east-1)"
  type        = list(string)
  default     = ["use1-az3"]
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
