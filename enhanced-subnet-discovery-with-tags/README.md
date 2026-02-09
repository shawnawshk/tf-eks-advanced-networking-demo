# EKS with Enhanced Subnet Discovery (Tag-Based)

Terraform configuration for deploying an Amazon EKS cluster using the VPC CNI **enhanced subnet discovery** feature. Instead of creating per-AZ ENIConfig CRDs (as required by custom networking), this approach uses **subnet tags** to let the VPC CNI automatically discover which subnets to use for pod IP allocation.

## Architecture

```
VPC (10.8.0.0/16)
├── Primary CIDR: 10.8.0.0/16
│   ├── Private Subnets (per AZ, /20) ─ Node IPs, EKS control plane
│   └── Public Subnets  (per AZ, /20) ─ Load balancers, NAT gateways
├── Secondary CIDR: 10.1.0.0/16
│   ├── AZ-a: 10.1.0.0/17   ─ Pod IPs (tagged kubernetes.io/role/cni=1)
│   └── AZ-b: 10.1.128.0/17
├── Secondary CIDR: 10.2.0.0/16
│   ├── AZ-c: 10.2.0.0/17
│   └── AZ-d: 10.2.128.0/17
└── Secondary CIDR: 10.3.0.0/16
    ├── AZ-e: 10.3.0.0/17
    └── AZ-f: 10.3.128.0/17
```

## Enhanced Subnet Discovery vs Custom Networking

| | Custom Networking | Enhanced Subnet Discovery |
|---|---|---|
| **CNI Config** | `AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true` | `ENABLE_SUBNET_DISCOVERY=true` |
| **Subnet Mapping** | ENIConfig CRD per AZ (manual mapping) | Tag-based auto-discovery |
| **Required CRDs** | ENIConfig per AZ | None |
| **Node Group Ordering** | Must wait for ENIConfig creation | No dependency chain |
| **Subnet Tag** | N/A | `kubernetes.io/role/cni=1` |

The key advantage: **no ENIConfig CRDs** and **no complex dependency ordering** between the CNI addon, CRDs, and node groups.

## Key Configurations

### 1. VPC CNI Addon - Enable Subnet Discovery

```hcl
# eks.tf
cluster_addons = {
  vpc-cni = {
    configuration_values = jsonencode({
      env = {
        ENABLE_PREFIX_DELEGATION = "true"
        WARM_PREFIX_TARGET       = "1"
        ENABLE_SUBNET_DISCOVERY  = "true"   # <-- the key setting
      }
    })
  }
}
```

### 2. Subnet Tagging - Tell CNI Where to Allocate Pod IPs

```hcl
# vpc.tf
resource "aws_ec2_tag" "secondary_cni" {
  count       = length(local.secondary_subnet_ids)
  resource_id = local.secondary_subnet_ids[count.index]
  key         = "kubernetes.io/role/cni"    # <-- CNI discovers subnets by this tag
  value       = "1"
}
```

### 3. Karpenter EC2NodeClass - Subnet Selection via Tags

```yaml
# karpenter.tf - EC2NodeClass
spec:
  subnetSelectorTerms:
  - tags:
      karpenter.sh/discovery: <cluster-name>
      kubernetes.io/role/cni: "1"           # <-- targets only secondary CIDR subnets
```

### 4. Node Groups - No ENIConfig Dependency

```hcl
# node_groups.tf - nodes launch on primary CIDR subnets
# CNI automatically assigns pod IPs from tagged secondary subnets
# No depends_on for ENIConfig needed
module "eks_managed_node_group" {
  subnet_ids = local.eks_private_subnet_ids  # primary CIDR subnets
  # ...
}
```

## Files

| File | Description |
|---|---|
| `main.tf` | Provider configuration, locals, AZ/subnet calculations |
| `vpc.tf` | VPC module with primary + secondary CIDRs, subnet tagging |
| `eks.tf` | EKS cluster, VPC CNI with `ENABLE_SUBNET_DISCOVERY`, Fargate profiles |
| `node_groups.tf` | Managed node group (no ENIConfig dependency needed) |
| `addons.tf` | EKS Blueprints addons (ALB Controller, EFS CSI, metrics-server) |
| `karpenter.tf` | Karpenter module, Helm release, EC2NodeClass, and NodePool |
| `variables.tf` | Input variables |
| `outputs.tf` | Output values |

## Prerequisites

- Terraform >= 1.3
- AWS CLI configured with appropriate credentials
- `kubectl` installed
- `helm` installed

## Usage

```bash
terraform init
terraform plan -out=tfplan
terraform apply "tfplan"

# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name enhanced-networking
```

## Variables

| Name | Description | Default |
|---|---|---|
| `region` | AWS region | `us-east-1` |
| `name` | Name prefix for resources | `enhanced-networking` |
| `vpc_cidr` | Primary VPC CIDR block | `10.8.0.0/16` |
| `secondary_cidrs` | Secondary CIDR blocks for pod networking | `["10.1.0.0/16", "10.2.0.0/16", "10.3.0.0/16"]` |
| `eks_unsupported_az_ids` | AZ IDs to exclude from EKS | `["use1-az3"]` |
| `tags` | Tags to apply to all resources | `{}` |

## Notes

- **Karpenter** runs on Fargate (via Fargate profiles) and uses IRSA for authentication (Fargate does not support Pod Identity).
- **CoreDNS** also runs on Fargate with autoscaling enabled (2-100 replicas).
- **kube-proxy** is configured in IPVS mode with round-robin scheduling.
- **NAT Gateway** is configured with one per AZ for high availability.
- **Secondary CIDRs** use `10.x.0.0/16` ranges. Each /16 provides two /17 subnets (~32k IPs each), totaling ~192k pod IPs across 6 AZs.
