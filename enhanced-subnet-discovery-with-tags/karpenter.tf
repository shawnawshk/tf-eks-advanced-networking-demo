locals {
  karpenter_namespace = "karpenter"
  karpenter_version   = "1.9.0"
}

data "aws_iam_policy_document" "karpenter_irsa" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:${local.karpenter_namespace}:karpenter"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.15"

  cluster_name = module.eks.cluster_name
  namespace    = local.karpenter_namespace

  # Name needs to match role name passed to the EC2NodeClass
  node_iam_role_use_name_prefix = false
  node_iam_role_name            = local.name

  # EKS Fargate does not support pod identity; use IRSA instead
  create_pod_identity_association = false
  iam_role_source_assume_policy_documents = [
    data.aws_iam_policy_document.karpenter_irsa.json
  ]

  tags = local.tags
}

resource "helm_release" "karpenter_crd" {
  name             = "karpenter-crd"
  namespace        = local.karpenter_namespace
  create_namespace = true
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter-crd"
  version          = local.karpenter_version

  lifecycle {
    ignore_changes = [repository_password]
  }
}

resource "helm_release" "karpenter" {
  name             = "karpenter"
  namespace        = local.karpenter_namespace
  create_namespace = true
  repository       = "oci://public.ecr.aws/karpenter"

  chart   = "karpenter"
  version = local.karpenter_version
  wait    = true

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
  depends_on = [helm_release.karpenter]

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
    subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: ${module.eks.cluster_name}
        kubernetes.io/role/cni: "1"
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
