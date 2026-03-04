module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.31"

  cluster_name          = module.eks.cluster_name
  enable_v1_permissions = true
  namespace             = local.namespace

  # Name needs to match role name passed to the EC2NodeClass
  node_iam_role_use_name_prefix = false
  node_iam_role_name            = local.name

  # EKS Fargate does not support pod identity
  create_pod_identity_association = false
  enable_irsa                     = true
  irsa_oidc_provider_arn          = module.eks.oidc_provider_arn

  tags = local.tags
}


resource "helm_release" "karpenter" {
  name             = "karpenter"
  namespace        = local.namespace
  create_namespace = true
  repository       = "oci://public.ecr.aws/karpenter"

  chart   = "karpenter"
  version = "1.6.1"
  wait    = true
  timeout = 600 # Fargate cold start can take 1-2 min; 10 min gives sufficient headroom

  values = [
    <<-EOT
    dnsPolicy: Default
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: ${module.karpenter.iam_role_arn}
    webhook:
      enabled: false
    controller:
      resources:
        limits:
          cpu: 1
          memory: 1Gi
    EOT
  ]

  lifecycle {
    ignore_changes = [
      repository_password
    ]
  }
}


################################################################################
# Karpenter Node Class & Node Pool
################################################################################

resource "kubectl_manifest" "karpenter_node_class" {
  depends_on = [helm_release.karpenter, kubectl_manifest.eniconfig]

  yaml_body = <<-YAML
  apiVersion: karpenter.k8s.aws/v1
  kind: EC2NodeClass
  metadata:
    name: default
  spec:
    amiSelectorTerms:
    - alias: al2023@latest
    kubelet:
      maxPods: 216
    instanceStorePolicy: RAID0
    blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        encrypted: true
        volumeSize: 500Gi
        volumeType: gp3
    role: ${module.eks.cluster_name}
    # Nodes are placed in primary CIDR private subnets (10.8.x.x, tagged kubernetes.io/role/internal-elb).
    # Pod IPs come from secondary CIDRs (100.64-66.x.x) via ENIConfig — that is controlled by VPC CNI, not Karpenter.
    # Do NOT change this to secondary-cidr subnets; intra subnets have no NAT route and node bootstrap will fail.
    subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: ${module.eks.cluster_name}
        kubernetes.io/role/internal-elb: "1"
    securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: ${module.eks.cluster_name}
    tags:
      karpenter.sh/discovery: ${module.eks.cluster_name}
  YAML
}

resource "kubectl_manifest" "karpenter_node_pool" {
  depends_on = [
    helm_release.karpenter,
    kubectl_manifest.karpenter_node_class
  ]
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: default
    spec:
      template:
        spec:
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default
          requirements:
          - key: node.kubernetes.io/instance-type
            operator: In
            values:
            - m6g.8xlarge
            - m6g.12xlarge
            - m6g.16xlarge
            - m7g.8xlarge
            - m7g.16xlarge
            - m8g.8xlarge
            - m8g.12xlarge
            - m8g.16xlarge
            - m8g.24xlarge
            - m8g.48xlarge
            - r6g.8xlarge
            - r6g.12xlarge
            - r6g.16xlarge
            - r7g.8xlarge
            - r7g.12xlarge
            - r7g.16xlarge
            - r8g.8xlarge
            - r8g.12xlarge
            - r8g.16xlarge
            - r8g.24xlarge
          - key: karpenter.sh/capacity-type
            operator: In
            values: ["on-demand"]
          - key: "karpenter.k8s.aws/instance-hypervisor"
            operator: In
            values: [ "nitro" ]
      limits:
        cpu: 150000
      disruption:
        consolidationPolicy: WhenEmpty
        consolidateAfter: 300s
    YAML
}
