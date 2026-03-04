# EKS with VPC CNI Custom Networking

Terraform configuration for deploying an Amazon EKS cluster with VPC CNI custom networking using secondary CIDR blocks. This setup separates node IPs (primary CIDR) from pod IPs (secondary CIDRs) to maximize available IP addresses for pods.

## Architecture

```
VPC (10.8.0.0/16)
├── Primary CIDR: 10.8.0.0/16
│   ├── Private Subnets (6x /20) - Node IPs, EKS control plane
│   └── Public Subnets  (6x /20) - Load balancers, NAT gateways
├── Secondary CIDR: 100.64.0.0/16
│   ├── us-east-1a: 100.64.0.0/17   (intra subnet - Pod IPs)
│   └── us-east-1b: 100.64.128.0/17
├── Secondary CIDR: 100.65.0.0/16
│   ├── us-east-1c: 100.65.0.0/17
│   └── us-east-1d: 100.65.128.0/17
└── Secondary CIDR: 100.66.0.0/16
    ├── us-east-1e: 100.66.0.0/17
    └── us-east-1f: 100.66.128.0/17
```

### Resource Dependency Chain

The deployment order is critical for VPC CNI custom networking to work correctly:

```
VPC + Subnets
  → EKS Cluster + VPC CNI Addon (with custom networking enabled)
    → ENIConfig CRDs (one per AZ, mapping to secondary CIDR subnets)
      → Managed Node Groups (nodes join with CNI already configured)
        → Addons (ALB Controller, EFS CSI, Karpenter, etc.)
```

Node groups are created as a **standalone module** (not inside `module.eks`) to enforce this ordering via `depends_on`. Without this, nodes would launch before ENIConfigs exist, causing the CNI to fail with `NetworkPluginNotReady`.

## Files

| File | Description |
|---|---|
| `main.tf` | Provider configuration, locals, AZ/subnet calculations |
| `vpc.tf` | VPC module with primary and secondary CIDRs |
| `eks.tf` | EKS cluster, addons (VPC CNI, CoreDNS, kube-proxy), Fargate profiles |
| `eniconfig.tf` | ENIConfig CRDs for VPC CNI custom networking |
| `node_groups.tf` | Managed node group (separated from EKS module for dependency ordering) |
| `addons.tf` | EKS Blueprints addons (ALB Controller, EFS CSI, metrics-server) |
| `karpenter.tf` | Karpenter module, Helm release, EC2NodeClass, and NodePool |
| `variables.tf` | Input variables |
| `outputs.tf` | Output values |

## VPC CNI Custom Networking

Custom networking is enabled via the VPC CNI addon configuration:

- `AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG = "true"` - Enables custom networking
- `ENI_CONFIG_LABEL_DEF = "topology.kubernetes.io/zone"` - Auto-selects ENIConfig by node AZ
- `ENABLE_PREFIX_DELEGATION = "true"` - Assigns /28 prefixes instead of individual IPs for higher pod density

Each AZ has an ENIConfig that maps to the corresponding intra subnet (secondary CIDR). When a node launches, the VPC CNI:
1. Reads the node's AZ label
2. Finds the matching ENIConfig
3. Creates secondary ENIs in the specified secondary CIDR subnet
4. Assigns pod IPs from that subnet

## Karpenter

Karpenter runs on Fargate (via Fargate profiles) and manages Graviton-based node pools:

- **EC2NodeClass**: Uses `al2023@latest` AMI, targets **primary CIDR private subnets** tagged with `kubernetes.io/role/internal-elb: "1"` (10.8.x.x). Pod IPs come from secondary CIDRs via ENIConfig — that routing is handled by VPC CNI, not Karpenter.
- **NodePool**: Graviton instances (m6g/m7g/m8g/r6g/r7g/r8g), on-demand, Nitro hypervisor, 75k vCPU limit
- **Authentication**: IRSA (Fargate does not support Pod Identity)

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
aws eks update-kubeconfig --region us-east-1 --name eks-networking
```

## Variables

| Name | Description | Default |
|---|---|---|
| `region` | AWS region | `us-east-1` |
| `name` | Name prefix for resources | `eks-networking` |
| `vpc_cidr` | Primary VPC CIDR block | `10.8.0.0/16` |
| `secondary_cidrs` | Secondary CIDR blocks for pod networking | `["100.64.0.0/16", "100.65.0.0/16", "100.66.0.0/16"]` |
| `tags` | Tags to apply to all resources | `{}` |

## Notes

- **us-east-1e**: EKS control plane does not support this AZ. The cluster uses 5 AZs (a,b,c,d,f) while the VPC spans all 6. Worker nodes can still run in us-east-1e via Karpenter.
- **NAT Gateway**: Configured with a single NAT gateway. Change `single_nat_gateway = false` in `vpc.tf` for one NAT per AZ (higher availability, higher cost).
- **Secondary CIDRs**: Uses RFC 6598 `100.64.0.0/10` range. Each /16 CIDR provides two /17 subnets (~32k IPs each), totaling ~196k pod IPs across all 6 AZs.
