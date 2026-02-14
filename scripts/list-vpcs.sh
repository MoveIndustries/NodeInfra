#!/usr/bin/env bash
set -euo pipefail

PROFILE=${AWS_PROFILE:-mi:scratchpad}
REGION=${AWS_REGION:-us-east-1}

export AWS_PROFILE="$PROFILE"
export AWS_SDK_LOAD_CONFIG=1

regions=$(aws ec2 describe-regions --region "$REGION" --query "Regions[].RegionName" --output text)
if [ -z "$regions" ]; then
  echo "No regions returned" >&2
  exit 1
fi

echo "Regions: $regions"

for region in $regions; do
  echo "==> $region"

  echo "-- VPCs --"
  aws ec2 describe-vpcs --region "$region" \
    --query "Vpcs[].{VpcId:VpcId,IsDefault:IsDefault,CreatedAt:CidrBlockAssociationSet[0].AssociationTime,Name:Tags[?Key==\`Name\`]|[0].Value,Validator:Tags[?Key==\`Validator\`]|[0].Value,Project:Tags[?Key==\`Project\`]|[0].Value}" \
    --output table || true

  echo "-- EKS clusters and VPCs --"
  clusters=$(aws eks list-clusters --region "$region" --query "clusters[]" --output text 2>/dev/null || true)
  if [ -z "$clusters" ]; then
    echo "  (none)"
  else
    for c in $clusters; do
      vpc_id=$(aws eks describe-cluster --region "$region" --name "$c" --query "cluster.resourcesVpcConfig.vpcId" --output text 2>/dev/null || true)
      echo "  $c -> $vpc_id"
    done
  fi

  echo ""
done
