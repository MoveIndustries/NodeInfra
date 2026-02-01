# Hello World Example

This example demonstrates the Movement validator infrastructure modules by deploying a simple HTTP echo service on EKS.

## What This Creates

- **VPC**: Isolated network with public/private subnets across 2 AZs
- **EKS Cluster**: Kubernetes 1.35 cluster with 1 node
- **Hello World App**: 2-replica HTTP echo service
- **Load Balancer**: Public Network Load Balancer
- **Optional DNS**: Route53 A record (if configured)

## Architecture

```
┌──────────────────────────────────────────────────┐
│              VPC (10.0.0.0/20)                   │
│                                                  │
│  ┌────────────────────────────────────────────┐ │
│  │  EKS Cluster: hello-world-cluster         │ │
│  │                                            │ │
│  │  ┌──────────────────────────────────────┐ │ │
│  │  │  Namespace: demo                     │ │ │
│  │  │                                      │ │ │
│  │  │  ┌────────────┐  ┌────────────┐    │ │ │
│  │  │  │ Hello World│  │ Hello World│    │ │ │
│  │  │  │  Pod #1    │  │  Pod #2    │    │ │ │
│  │  │  │  (5678)    │  │  (5678)    │    │ │ │
│  │  │  └────────────┘  └────────────┘    │ │ │
│  │  │         ▲              ▲            │ │ │
│  │  │         └──────┬───────┘            │ │ │
│  │  │                │                    │ │ │
│  │  │      ┌─────────▼────────┐          │ │ │
│  │  │      │  Service (NLB)    │          │ │ │
│  │  │      │  Port: 80         │          │ │ │
│  │  │      └─────────┬────────┘          │ │ │
│  │  └────────────────┼───────────────────┘ │ │
│  └───────────────────┼─────────────────────┘ │
│                      │                        │
│  ┌───────────────────▼─────────────────────┐ │
│  │  Network Load Balancer (Public)         │ │
│  │  abc123.elb.us-east-1.amazonaws.com     │ │
│  └─────────────────────────────────────────┘ │
└──────────────────────────────────────────────────┘
                      ▲
                      │
                Internet
```

## Prerequisites

1. **AWS Account** with appropriate permissions
2. **AWS CLI** configured with credentials
3. **Terraform** >= 1.9.0
4. **kubectl** (optional, for cluster access)

## Quick Start

### 1. Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

Minimal configuration:
```hcl
validator_name = "hello-world"
region         = "us-east-1"
```

### 2. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply (takes ~10-15 minutes)
terraform apply
```

### 3. Test Hello World

Once deployment completes, get the load balancer URL:

```bash
# Get the URL from outputs
terraform output hello_world_url

# Test with curl
curl $(terraform output -raw hello_world_url)
```

Expected response:
```
Hello World from Movement Validator Infrastructure! 🚀
```

### 4. Access Kubernetes (Optional)

```bash
# Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name hello-world-cluster

# Check nodes
kubectl get nodes

# Check pods
kubectl get pods -n demo

# Check service
kubectl get svc -n demo
```

### 5. Cleanup

```bash
# Destroy all resources
terraform destroy
```

## Cost Estimate

Running this example costs approximately:

| Resource | Cost | Notes |
|----------|------|-------|
| EKS Control Plane | $0.10/hour (~$73/month) | Fixed cost per cluster |
| EC2 t3.xlarge | $0.166/hour (~$120/month) | 4 vCPU, 16GB RAM |
| NAT Gateway | $0.045/hour (~$32/month) | Single NAT for cost optimization |
| EBS Storage (50GB) | $0.08/GB/month (~$4/month) | Node root volume |
| Network Load Balancer | $0.0225/hour (~$16/month) | Public load balancer |
| Data Transfer | Variable | Depends on usage |
| **Total** | **~$245/month** | **$0.34/hour** |

💡 **Cost Optimization Tips:**
- This is a demo - destroy when not in use
- Use spot instances for production (70% savings)
- Consider smaller instance types for testing

## What's Deployed

### Network Layer (module.network)
- VPC with CIDR 10.0.0.0/20
- 2 public subnets (10.0.0.0/24, 10.0.1.0/24)
- 2 private subnets (10.0.2.0/24, 10.0.3.0/24)
- Internet Gateway
- Single NAT Gateway (cost optimized)
- Security groups for EKS and load balancers

### Compute Layer (module.eks)
- EKS cluster (Kubernetes 1.35)
- Managed node group (1 t3.xlarge instance)
- EBS CSI driver addon
- IRSA (IAM Roles for Service Accounts)
- CloudWatch logging (3-day retention)

### Application Layer
- Namespace: `demo`
- Deployment: 2 replicas of hashicorp/http-echo
- Service: Network Load Balancer on port 80
- Health checks: liveness and readiness probes

## Outputs

After `terraform apply`, you'll see:

```
Outputs:

cluster_endpoint = "https://ABC123.gr7.us-east-1.eks.amazonaws.com"
cluster_name = "hello-world-cluster"
configure_kubectl = "aws eks update-kubeconfig --region us-east-1 --name hello-world-cluster"
hello_world_url = "http://abc123-nlb.elb.us-east-1.amazonaws.com"
load_balancer_hostname = "abc123-nlb.elb.us-east-1.amazonaws.com"
vpc_id = "vpc-0123456789abcdef"
```

## Troubleshooting

### Load Balancer Pending
If the load balancer shows "pending", wait 2-3 minutes for AWS to provision it:

```bash
# Watch the service status
kubectl get svc -n demo -w
```

### Pods Not Starting
Check pod logs:

```bash
kubectl describe pod -n demo -l app=hello-world
kubectl logs -n demo -l app=hello-world
```

### Cannot Connect to Cluster
Ensure AWS credentials are configured:

```bash
aws sts get-caller-identity
aws eks update-kubeconfig --region us-east-1 --name hello-world-cluster
```

### Terraform Apply Fails
Common issues:
- **AWS credentials**: Check `aws configure`
- **Region availability**: Ensure EKS is available in your region
- **Service quotas**: Check AWS service quotas for VPCs, EIPs, EKS

## Next Steps

After validating this example works:

1. **Explore the modules**: Review `terraform-modules/` for module details
2. **Deploy a validator**: See Milestone 2 for Aptos validator deployment
3. **Customize**: Modify variables for your use case
4. **Add monitoring**: Integrate with observability stack (Milestone 4)

## Module Documentation

- [movement-network-base](../../terraform-modules/movement-network-base/README.md)
- [movement-validator-infra](../../terraform-modules/movement-validator-infra/README.md)

## Support

For issues or questions:
- Review module READMEs
- Check Terraform logs: `TF_LOG=DEBUG terraform apply`
- Open an issue in the GitHub repository
