#!/usr/bin/env bash
set -euo pipefail

PROFILE=${AWS_PROFILE:-mi:scratchpad}
REGION=${AWS_REGION:-us-east-1}

export AWS_PROFILE="$PROFILE"
export AWS_SDK_LOAD_CONFIG=1

aws sts get-caller-identity >/dev/null

regions=$(aws ec2 describe-regions --region "$REGION" --query "Regions[].RegionName" --output text)
if [ -z "$regions" ]; then
  echo "No regions returned" >&2
  exit 1
fi

echo "Regions: $regions"

for region in $regions; do
  echo "==> $region"
  vpcs=$(aws ec2 describe-vpcs --region "$region" --query "Vpcs[].VpcId" --output text || true)
  if [ -z "$vpcs" ]; then
    echo "  No VPCs in $region"
    continue
  fi

  # Build cluster->vpc mapping
  clusters=$(aws eks list-clusters --region "$region" --query "clusters[]" --output text 2>/dev/null || true)
  cluster_vpc_map=""
  if [ -n "$clusters" ]; then
    for c in $clusters; do
      vpc_id=$(aws eks describe-cluster --region "$region" --name "$c" --query "cluster.resourcesVpcConfig.vpcId" --output text 2>/dev/null || true)
      if [ -n "$vpc_id" ] && [ "$vpc_id" != "None" ]; then
        cluster_vpc_map+="$vpc_id $c"$'\n'
      fi
    done
  fi

  for vpc in $vpcs; do
    meta=$(aws ec2 describe-vpcs --region "$region" --vpc-ids "$vpc" \
      --query "Vpcs[0].{IsDefault:IsDefault,Name:Tags[?Key==\`Name\`]|[0].Value,Project:Tags[?Key==\`Project\`]|[0].Value,Validator:Tags[?Key==\`Validator\`]|[0].Value}" \
      --output text 2>/dev/null || true)
    if [ -z "$meta" ] || [ "$meta" = "None" ]; then
      echo "  -> Skipping VPC $vpc (metadata unavailable)"
      continue
    fi

    IFS=$'\t' read -r is_default name project validator <<< "$meta"
    name=${name:-None}
    project=${project:-None}
    validator=${validator:-None}

    if [ "$is_default" = "True" ]; then
      echo "  -> Skipping VPC $vpc (default VPC)"
      continue
    fi

    if [ "$project" != "movement-validator" ] && \
       { [ -z "$validator" ] || [ "$validator" = "None" ]; } && \
       [[ "$name" != pfn-* ]]; then
      echo "  -> Skipping VPC $vpc (not repo-created)"
      continue
    fi

    echo "  -> Cleaning VPC $vpc"

    # Delete EKS clusters in this VPC
    if [ -n "$cluster_vpc_map" ]; then
      while read -r map_vpc map_cluster; do
        if [ "$map_vpc" = "$vpc" ]; then
          echo "    Deleting EKS cluster $map_cluster"
          addons=$(aws eks list-addons --region "$region" --cluster-name "$map_cluster" --query "addons[]" --output text 2>/dev/null || true)
          if [ -n "$addons" ]; then
            for addon in $addons; do
              aws eks delete-addon --region "$region" --cluster-name "$map_cluster" --addon-name "$addon" >/dev/null 2>&1 || true
            done
          fi

          nodegroups=$(aws eks list-nodegroups --region "$region" --cluster-name "$map_cluster" --query "nodegroups[]" --output text 2>/dev/null || true)
          if [ -n "$nodegroups" ]; then
            for ng in $nodegroups; do
              aws eks delete-nodegroup --region "$region" --cluster-name "$map_cluster" --nodegroup-name "$ng" >/dev/null 2>&1 || true
            done
            for ng in $nodegroups; do
              aws eks wait nodegroup-deleted --region "$region" --cluster-name "$map_cluster" --nodegroup-name "$ng" >/dev/null 2>&1 || true
            done
          fi

          aws eks delete-cluster --region "$region" --name "$map_cluster" >/dev/null 2>&1 || true
          aws eks wait cluster-deleted --region "$region" --name "$map_cluster" >/dev/null 2>&1 || true
        fi
      done <<< "$cluster_vpc_map"
    fi

    # Delete load balancers (v2)
    lbs=$(aws elbv2 describe-load-balancers --region "$region" --query "LoadBalancers[?VpcId=='$vpc'].LoadBalancerArn" --output text 2>/dev/null || true)
    if [ -n "$lbs" ]; then
      for lb in $lbs; do
        aws elbv2 delete-load-balancer --region "$region" --load-balancer-arn "$lb" >/dev/null 2>&1 || true
      done
    fi

    # Delete VPC endpoints
    vpc_endpoints=$(aws ec2 describe-vpc-endpoints --region "$region" --filters Name=vpc-id,Values="$vpc" --query "VpcEndpoints[].VpcEndpointId" --output text 2>/dev/null || true)
    if [ -n "$vpc_endpoints" ]; then
      aws ec2 delete-vpc-endpoints --region "$region" --vpc-endpoint-ids $vpc_endpoints >/dev/null 2>&1 || true
    fi

    # Delete NAT gateways and release EIPs
    nat_ids=$(aws ec2 describe-nat-gateways --region "$region" --filter Name=vpc-id,Values="$vpc" --query "NatGateways[].NatGatewayId" --output text 2>/dev/null || true)
    nat_eips=$(aws ec2 describe-nat-gateways --region "$region" --filter Name=vpc-id,Values="$vpc" --query "NatGateways[].NatGatewayAddresses[].AllocationId" --output text 2>/dev/null || true)
    if [ -n "$nat_ids" ]; then
      for nat in $nat_ids; do
        aws ec2 delete-nat-gateway --region "$region" --nat-gateway-id "$nat" >/dev/null 2>&1 || true
      done
      for nat in $nat_ids; do
        aws ec2 wait nat-gateway-deleted --region "$region" --nat-gateway-id "$nat" >/dev/null 2>&1 || true
      done
    fi
    if [ -n "$nat_eips" ]; then
      for alloc in $nat_eips; do
        aws ec2 release-address --region "$region" --allocation-id "$alloc" >/dev/null 2>&1 || true
      done
    fi

    # Detach and delete internet gateways
    igws=$(aws ec2 describe-internet-gateways --region "$region" --filters Name=attachment.vpc-id,Values="$vpc" --query "InternetGateways[].InternetGatewayId" --output text 2>/dev/null || true)
    if [ -n "$igws" ]; then
      for igw in $igws; do
        aws ec2 detach-internet-gateway --region "$region" --internet-gateway-id "$igw" --vpc-id "$vpc" >/dev/null 2>&1 || true
        aws ec2 delete-internet-gateway --region "$region" --internet-gateway-id "$igw" >/dev/null 2>&1 || true
      done
    fi

    # Disassociate non-main route table associations
    assoc_ids=$(aws ec2 describe-route-tables --region "$region" --filters Name=vpc-id,Values="$vpc" --query "RouteTables[].Associations[?Main==\`false\`].RouteTableAssociationId" --output text 2>/dev/null || true)
    if [ -n "$assoc_ids" ]; then
      for assoc in $assoc_ids; do
        aws ec2 disassociate-route-table --region "$region" --association-id "$assoc" >/dev/null 2>&1 || true
      done
    fi

    # Delete non-main route tables
    rt_ids=$(aws ec2 describe-route-tables --region "$region" --filters Name=vpc-id,Values="$vpc" --query "RouteTables[].RouteTableId" --output text 2>/dev/null || true)
    if [ -n "$rt_ids" ]; then
      for rt in $rt_ids; do
        is_main=$(aws ec2 describe-route-tables --region "$region" --route-table-ids "$rt" --query "RouteTables[0].Associations[?Main==\`true\`].RouteTableAssociationId" --output text 2>/dev/null || true)
        if [ -z "$is_main" ]; then
          aws ec2 delete-route-table --region "$region" --route-table-id "$rt" >/dev/null 2>&1 || true
        fi
      done
    fi

    # Delete available ENIs
    enis=$(aws ec2 describe-network-interfaces --region "$region" --filters Name=vpc-id,Values="$vpc" --query "NetworkInterfaces[?Status==\`available\`].NetworkInterfaceId" --output text 2>/dev/null || true)
    if [ -n "$enis" ]; then
      for eni in $enis; do
        aws ec2 delete-network-interface --region "$region" --network-interface-id "$eni" >/dev/null 2>&1 || true
      done
    fi

    # Delete subnets
    subnets=$(aws ec2 describe-subnets --region "$region" --filters Name=vpc-id,Values="$vpc" --query "Subnets[].SubnetId" --output text 2>/dev/null || true)
    if [ -n "$subnets" ]; then
      for subnet in $subnets; do
        aws ec2 delete-subnet --region "$region" --subnet-id "$subnet" >/dev/null 2>&1 || true
      done
    fi

    # Delete non-default security groups
    sgs=$(aws ec2 describe-security-groups --region "$region" --filters Name=vpc-id,Values="$vpc" --query "SecurityGroups[?GroupName!=\`default\`].GroupId" --output text 2>/dev/null || true)
    if [ -n "$sgs" ]; then
      for sg in $sgs; do
        aws ec2 delete-security-group --region "$region" --group-id "$sg" >/dev/null 2>&1 || true
      done
    fi

    # Delete non-default network ACLs
    nacls=$(aws ec2 describe-network-acls --region "$region" --filters Name=vpc-id,Values="$vpc" --query "NetworkAcls[?IsDefault==\`false\`].NetworkAclId" --output text 2>/dev/null || true)
    if [ -n "$nacls" ]; then
      for nacl in $nacls; do
        aws ec2 delete-network-acl --region "$region" --network-acl-id "$nacl" >/dev/null 2>&1 || true
      done
    fi

    # Finally delete VPC
    aws ec2 delete-vpc --region "$region" --vpc-id "$vpc" >/dev/null 2>&1 || true
  done

done

echo "VPC cleanup attempt complete."
