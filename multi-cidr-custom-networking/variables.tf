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
  default     = ["100.64.0.0/16", "100.65.0.0/16", "100.66.0.0/16"]
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
