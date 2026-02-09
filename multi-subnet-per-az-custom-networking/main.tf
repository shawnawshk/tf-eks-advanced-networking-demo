terraform {
  required_version = ">= 1.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.34"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.9"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14"
    }
  }
}


provider "aws" {
  region = var.region
}

provider "aws" {
  alias  = "ecr"
  region = "us-east-1"
}


provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
  load_config_file       = false
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }

  registry {
    url      = "oci://public.ecr.aws"
    username = data.aws_ecrpublic_authorization_token.token.user_name
    password = data.aws_ecrpublic_authorization_token.token.password
  }
}



data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.ecr
}

data "aws_availability_zones" "available" {
  # Do not include local zones
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }

  # Exclude AZ IDs that don't support EKS control plane
  exclude_zone_ids = var.eks_unsupported_az_ids
}
locals {
  azs = data.aws_availability_zones.available.names

  # Primary CIDR subnets (10.8.0.0/16) - 5x /20
  private_subnets = [for i in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 4, i + length(local.azs))]

  # Secondary CIDR subnets - 2x /17 per /16 CIDR, round-robin across 5 AZs
  # 20 CIDRs x 2 subnets = 40 intra subnets, 8 per AZ
  intra_subnets = flatten([
    for cidr in var.secondary_cidrs : [
      cidrsubnet(cidr, 1, 0),
      cidrsubnet(cidr, 1, 1),
    ]
  ])

  num_azs = length(local.azs)

  # Map of ENIConfig name -> { az, subnet_id } for all 40 intra subnets
  # Naming: {az}-{per_az_index} e.g. us-east-1a-0 through us-east-1a-7
  # Intra subnets are round-robin across AZs, so index i maps to AZ i % num_azs
  # and the per-AZ index is floor(i / num_azs)
  eniconfig_map = {
    for i in range(length(local.intra_subnets)) :
    "${local.azs[i % local.num_azs]}-${floor(i / local.num_azs)}" => {
      az        = local.azs[i % local.num_azs]
      subnet_id = module.vpc.intra_subnets[i]
    }
  }
}

