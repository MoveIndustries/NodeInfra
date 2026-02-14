#!/bin/bash
set -e

# Only clean movement-validator VPCs, not the scratchpad VPC
VPC_IDS=("vpc-0ab4fb4b85f3d8519" "vpc-0575933eb1f862397" "vpc-09e72965614052aa7")
REGION="us-east-1"

for VPC_ID in "${VPC_IDS[@]}"; do
    echo "=== Cleaning VPC: $VPC_ID ==="
    
    # 1. Delete Load Balancers
    echo "  Deleting load balancers..."
    aws elbv2 describe-load-balancers --region $REGION 2>/dev/null | \
    jq -r ".LoadBalancers[] | select(.VpcId==\"$VPC_ID\") | .LoadBalancerArn" | \
    while read LB; do
        echo "    Deleting LB: $LB"
        aws elbv2 delete-load-balancer --region $REGION --load-balancer-arn "$LB" 2>/dev/null || true
    done
    
    # 2. Delete NAT Gateways
    echo "  Deleting NAT gateways..."
    aws ec2 describe-nat-gateways --region $REGION --filter "Name=vpc-id,Values=$VPC_ID" 2>/dev/null | \
    jq -r '.NatGateways[] | select(.State!="deleted") | .NatGatewayId' | \
    while read NAT; do
        echo "    Deleting NAT: $NAT"
        aws ec2 delete-nat-gateway --region $REGION --nat-gateway-id "$NAT" 2>/dev/null || true
    done
    
    # 3. Delete VPC Endpoints
    echo "  Deleting VPC endpoints..."
    aws ec2 describe-vpc-endpoints --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" 2>/dev/null | \
    jq -r '.VpcEndpoints[].VpcEndpointId' | \
    while read EP; do
        echo "    Deleting endpoint: $EP"
        aws ec2 delete-vpc-endpoints --region $REGION --vpc-endpoint-ids "$EP" 2>/dev/null || true
    done
done

echo "Waiting 20 seconds for async deletions..."
sleep 20

for VPC_ID in "${VPC_IDS[@]}"; do
    echo "=== Cleaning VPC resources: $VPC_ID ==="
    
    # 4. Delete Network Interfaces
    echo "  Deleting network interfaces..."
    aws ec2 describe-network-interfaces --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" 2>/dev/null | \
    jq -r '.NetworkInterfaces[].NetworkInterfaceId' | \
    while read ENI; do
        echo "    Deleting ENI: $ENI"
        aws ec2 delete-network-interface --region $REGION --network-interface-id "$ENI" 2>/dev/null || true
    done
    
    # 5. Detach and Delete Internet Gateways
    echo "  Deleting internet gateways..."
    aws ec2 describe-internet-gateways --region $REGION --filters "Name=attachment.vpc-id,Values=$VPC_ID" 2>/dev/null | \
    jq -r '.InternetGateways[].InternetGatewayId' | \
    while read IGW; do
        echo "    Detaching IGW: $IGW"
        aws ec2 detach-internet-gateway --region $REGION --internet-gateway-id "$IGW" --vpc-id "$VPC_ID" 2>/dev/null || true
        echo "    Deleting IGW: $IGW"
        aws ec2 delete-internet-gateway --region $REGION --internet-gateway-id "$IGW" 2>/dev/null || true
    done
    
    # 6. Delete Subnets
    echo "  Deleting subnets..."
    aws ec2 describe-subnets --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" 2>/dev/null | \
    jq -r '.Subnets[].SubnetId' | \
    while read SUBNET; do
        echo "    Deleting subnet: $SUBNET"
        aws ec2 delete-subnet --region $REGION --subnet-id "$SUBNET" 2>/dev/null || true
    done
    
    # 7. Delete Route Tables (non-main)
    echo "  Deleting route tables..."
    aws ec2 describe-route-tables --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" 2>/dev/null | \
    jq -r '.RouteTables[] | select(.Associations[].Main!=true) | .RouteTableId' | \
    while read RT; do
        echo "    Deleting route table: $RT"
        aws ec2 delete-route-table --region $REGION --route-table-id "$RT" 2>/dev/null || true
    done
    
    # 8. Delete Security Groups (non-default)
    echo "  Deleting security groups..."
    aws ec2 describe-security-groups --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" 2>/dev/null | \
    jq -r '.SecurityGroups[] | select(.GroupName!="default") | .GroupId' | \
    while read SG; do
        echo "    Deleting security group: $SG"
        aws ec2 delete-security-group --region $REGION --group-id "$SG" 2>/dev/null || true
    done
    
    # 9. Release Elastic IPs
    echo "  Releasing Elastic IPs..."
    aws ec2 describe-addresses --region $REGION 2>/dev/null | \
    jq -r '.Addresses[] | select(.AssociationId==null) | .AllocationId' | \
    while read EIP; do
        echo "    Releasing EIP: $EIP"
        aws ec2 release-address --region $REGION --allocation-id "$EIP" 2>/dev/null || true
    done
    
    # 10. Delete VPC
    echo "  Deleting VPC..."
    if aws ec2 delete-vpc --region $REGION --vpc-id "$VPC_ID" 2>/dev/null; then
        echo "    ✓ VPC $VPC_ID deleted!"
    else
        echo "    ✗ VPC $VPC_ID deletion failed (may have remaining dependencies)"
    fi
    echo ""
done

echo "Cleanup complete!"