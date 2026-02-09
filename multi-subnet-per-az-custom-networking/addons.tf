module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.0" #ensure to update this to the latest/desired version

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn
  # disable the Telemetry from AWS using CloudFormation
  observability_tag = null

  # Ensure Karpenter NodePools are ready so nodes can be provisioned for addons
  depends_on = [kubectl_manifest.karpenter_node_pool]

  eks_addons = {
    metrics-server = { most_recent = true }
  }

  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller = {
    chart_version = "1.14.1"
    set = [
      {
        name  = "vpcId" # explicitly set the vpcId, otherwise it may not able to retrieve the vpcId from the node
        value = module.vpc.vpc_id
      },
    ]
  }

  enable_ingress_nginx = false # as an example of the load balancer use case
  ingress_nginx = {
    chart_version = "4.12.1"
    values = [yamlencode({
      controller = {
        metrics = {
          enabled = true
          serviceMonitor = {
            enabled = false
            additionalLabels = {
              release = "kube-prometheus-stack"
            }
          }
        }
        podAnnotations = {
          "prometheus.io/port"   = "10254"
          "prometheus.io/scrape" = "true"
        }
        service = {
          type                  = "LoadBalancer"
          externalTrafficPolicy = "Local"
          annotations = {
            "service.beta.kubernetes.io/aws-load-balancer-type"             = "external"
            "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"  = "ip" # ip mode still works in custom networking
            "service.beta.kubernetes.io/aws-load-balancer-backend-protocol" = "tcp"
            "service.beta.kubernetes.io/aws-load-balancer-scheme"           = "internet-facing"
            "service.beta.kubernetes.io/aws-load-balancer-ssl-ports"        = "443"
          }
          targetPorts = {
            http  = "http"
            https = "http"
          }
        }
        autoscaling = {
          enabled     = true
          minReplicas = 2
          maxReplicas = 10
        }
        resources = {
          requests = {
            cpu    = "500m"
            memory = "256Mi"
          }
        }
      }
    })]
  }

  enable_aws_efs_csi_driver = true

  helm_releases = {
  }

  tags = merge(local.tags, {
    # NOTE - if creating multiple security groups with this module, only tag the
    # security group that Karpenter should utilize with the following tag
    # (i.e. - at most, only one security group should have this tag in your account)
    "Environment" = "dev"
  })
}
