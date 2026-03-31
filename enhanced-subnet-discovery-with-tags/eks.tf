locals {
  name = var.name
  tags = merge(var.tags, {
    "karpenter.sh/discovery" = local.name
  })
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.15"

  name               = local.name
  kubernetes_version = "1.35"

  # Give the Terraform identity admin access to the cluster
  # which will allow it to deploy resources into the cluster
  enable_cluster_creator_admin_permissions = true
  endpoint_public_access                   = true

  addons = {
    # Enable after creation to run on Karpenter managed nodes
    vpc-cni = {
      enabled                     = true
      most_recent                 = true
      resolve_conflicts_on_update = "OVERWRITE"
      before_compute              = true
      configuration_values = jsonencode({
        enableNetworkPolicy : "true"
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
          ENABLE_SUBNET_DISCOVERY  = "true"
        }
      })
    }
    coredns = {
      enabled                     = true
      most_recent                 = true
      resolve_conflicts_on_update = "OVERWRITE"
      configuration_values = jsonencode({
        nodeSelector = {
          "eks.amazonaws.com/compute-type" = "fargate"
        }
        autoScaling = {
          enabled     = true
          minReplicas = 2
          maxReplicas = 100 # change to the number which make sense to you
        }
        corefile = <<-EOF
          .:53 {
              errors
              health {
                  lameduck 10s
              }
              ready
              kubernetes cluster.local in-addr.arpa ip6.arpa {
                  pods insecure
                  fallthrough in-addr.arpa ip6.arpa
                  ttl 30
              }
              prometheus :9153
              forward . /etc/resolv.conf
              cache 30
              loop
              reload
              loadbalance
          }
        EOF
      })
    }
    kube-proxy = {
      most_recent                 = true
      resolve_conflicts_on_update = "OVERWRITE"
      configuration_values = jsonencode({
        mode = "ipvs"
        ipvs = {
          scheduler = "rr"
        }
      })
    }
  }

  # For migration to EKS Auto Mode only
  # bootstrap_self_managed_addons = true
  # cluster_compute_config = {
  #   enabled    = true
  #   node_pools = ["general-purpose", "system"]
  # }


  vpc_id     = module.vpc.vpc_id
  subnet_ids = local.eks_private_subnet_ids

  # Fargate profiles use the cluster primary security group
  # Therefore these are not used and can be skipped
  create_security_group      = false
  create_node_security_group = false

  fargate_profiles = {
    karpenter = {
      selectors = [
        { namespace = "karpenter" }
      ]
    }
    coredns = {
      selectors = [
        { namespace = "kube-system"
          labels = {
            k8s-app = "kube-dns"
          }
        }
      ]
    }
  }

  tags = local.tags
}
