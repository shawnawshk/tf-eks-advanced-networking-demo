# EKS Custom Networking: Multi-Subnets per AZ

Terraform configurations demonstrating how to run multiple subnets per Availability Zone in Amazon EKS using VPC CNI custom networking. By attaching secondary CIDR blocks to the VPC and placing pod ENIs on dedicated subnets separate from node subnets, each AZ ends up with multiple subnets serving distinct roles:

- **Primary subnets** -- for node ENIs, EKS control plane, and load balancers
- **Secondary subnets** -- exclusively for pod IPs, drawn from separate CIDR blocks

This pattern solves IP exhaustion in the primary CIDR while keeping node and pod networking cleanly separated.

## Repository Structure

```
.
├── multi-cidr-custom-networking/        # ENIConfig CRDs, 3 secondary CIDRs, 1 pod subnet per AZ
├── multi-subnet-per-az-custom-networking/ # ENIConfig CRDs, 20 secondary CIDRs, 8 pod subnets per AZ
└── enhanced-subnet-discovery-with-tags/ # Tag-based discovery, 3 secondary CIDRs, 1 pod subnet per AZ
```

## Examples

### 1. [Multi-CIDR Custom Networking](./multi-cidr-custom-networking/)

The traditional approach using **ENIConfig CRDs** to explicitly map each AZ to its secondary pod subnet.

- **VPC CNI config**: `AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true` with `ENI_CONFIG_LABEL_DEF=topology.kubernetes.io/zone`
- **Secondary CIDRs**: 3x /16 from RFC 6598 space (`100.64.0.0/16` -- `100.66.0.0/16`), each split into 2x /17, 1 pod subnet per AZ
- **Pod subnet type**: Intra (no NAT route) -- pods are not directly internet-routable
- **ENIConfigs**: 6 total (1 per AZ), named by AZ
- **Key detail**: Node groups must be created _after_ ENIConfig CRDs exist via `depends_on`, otherwise nodes fail with `NetworkPluginNotReady`

### 2. [Multi-Subnet per AZ Custom Networking](./multi-subnet-per-az-custom-networking/)

Scales the ENIConfig approach to **20 secondary CIDRs** with **8 pod subnets per AZ**, demonstrating how to maximize pod IP capacity (~1.31M IPs across 5 AZs).

- **VPC CNI config**: `AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true` with `ENI_CONFIG_LABEL_DEF=k8s.amazonaws.com/eniConfig` (custom label, set by Karpenter NodePools)
- **Secondary CIDRs**: 20x /16 from RFC 6598 space (`100.64.0.0/16` -- `100.83.0.0/16`), each split into 2x /17, round-robin across 5 AZs = 40 intra subnets, 8 per AZ
- **Pod subnet type**: Intra (no NAT route)
- **ENIConfigs**: 40 total, named `{az}-{index}` (e.g. `us-east-1a-0` through `us-east-1a-7`)
- **Karpenter**: Per-AZ NodePools label nodes with `k8s.amazonaws.com/eniConfig: {az}-{index}` to select the correct ENIConfig
- **Key detail**: Requires raising the VPC CIDR blocks quota above the default of 5. CIDRs from the `100.64.0.0/10` range have a separate higher limit.

### 3. [Enhanced Subnet Discovery with Tags](./enhanced-subnet-discovery-with-tags/)

A simpler approach that eliminates ENIConfig CRDs. The VPC CNI **auto-discovers** secondary pod subnets by the `kubernetes.io/role/cni: 1` tag.

- **VPC CNI config**: `ENABLE_SUBNET_DISCOVERY=true`
- **Secondary CIDRs**: 3x /16 from RFC 1918 space (`10.1.0.0/16` -- `10.3.0.0/16`), each split into 2x /17, 1 pod subnet per AZ
- **Pod subnet type**: Private (routable via NAT) -- pods can reach the internet
- **ENIConfigs**: None -- tag the subnets and the CNI handles AZ-to-subnet mapping automatically
- **Key detail**: No CRDs, no dependency ordering for node groups

## Comparison

| | multi-cidr-custom-networking | multi-subnet-per-az | enhanced-subnet-discovery |
|---|---|---|---|
| Secondary CIDRs | 3 | 20 | 3 |
| Pod subnets per AZ | 1 | 8 | 1 |
| Total pod IPs | ~196k | ~1.31M | ~196k |
| Pod subnet discovery | ENIConfig per AZ | ENIConfig per subnet | `kubernetes.io/role/cni` tag |
| ENIConfig count | 6 | 40 | 0 |
| Node group dependency | Depends on ENIConfig | Depends on ENIConfig | None |
| Pod subnet routing | Intra | Intra | Private (NAT) |

## Shared Infrastructure

All three configurations deploy:

- EKS v1.35 with Fargate profiles for Karpenter and CoreDNS
- Prefix delegation (`ENABLE_PREFIX_DELEGATION=true`) for higher pod density per node
- Karpenter managing Graviton instance pools (m6g/m7g/m8g, r6g/r7g/r8g)
- Addons: VPC CNI, CoreDNS, kube-proxy (IPVS), AWS Load Balancer Controller, EFS CSI Driver, metrics-server

## Prerequisites

- Terraform >= 1.3
- AWS CLI configured with appropriate credentials
- `kubectl` and `helm` installed

## Usage

```bash
cd <example-directory>
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```
