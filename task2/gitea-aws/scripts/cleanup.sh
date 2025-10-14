# gitea-aws/scripts/cleanup.sh
#!/usr/bin/env bash
set -euo pipefail

# -------- Config (safe defaults) --------
AWS_REGION="${AWS_REGION:-eu-central-1}"
export AWS_REGION AWS_DEFAULT_REGION="$AWS_REGION" AWS_PAGER="" AWS_CLI_PAGER=""

PREFIX="${PREFIX:-}"

TAG_PROJECT="${TAG_PROJECT:-}"
TAG_ENV="${TAG_ENV:-}"
TAG_MANAGED_BY="${TAG_MANAGED_BY:-terraform}"

DELETE_ALB="${DELETE_ALB:-true}"

# Optional: delete DB instance too (risky; defaults false)
DELETE_RDS_INSTANCE="${DELETE_RDS_INSTANCE:-false}"
DB_INSTANCE_IDENTIFIER="${DB_INSTANCE_IDENTIFIER:-${PREFIX:+${PREFIX}-postgres}}"

# Safety knobs
DRY_RUN="${DRY_RUN:-true}"           # print intended aws calls
DELETE_VPC_STACK="${DELETE_VPC_STACK:-false}"
DELETE_ENIS="${DELETE_ENIS:-true}"
DELETE_EIPS="${DELETE_EIPS:-false}"

say() { printf '%s\n' "$*"; }
hr()  { printf '%*s\n' "$(tput cols 2>/dev/null || echo 80)" '' | tr ' ' -; }
title(){ hr; say ">>> $*"; }
confirm(){ read -r -p "${1:-Proceed?} [y/N] " ans; [[ "$ans" =~ ^[yY]$ ]]; }

# Dry-run aware runner
do_aws() {
  if [[ "$DRY_RUN" == "true" ]]; then
    printf '[DRY_RUN] aws %s\n' "$*"
  else
    # shellcheck disable=SC2086
    aws "$@"
  fi
}

# ---------- Tag helpers ----------
tag_filters_rgt=()
[[ -n "$TAG_PROJECT"    ]] && tag_filters_rgt+=( "Key=Project,Values=$TAG_PROJECT" )
[[ -n "$TAG_ENV"        ]] && tag_filters_rgt+=( "Key=Environment,Values=$TAG_ENV" )
[[ -n "$TAG_MANAGED_BY" ]] && tag_filters_rgt+=( "Key=ManagedBy,Values=$TAG_MANAGED_BY" )

get_tagged_arns() {
  local res_type="$1"
  if [[ ${#tag_filters_rgt[@]} -eq 0 ]]; then
    return 0
  fi
  aws resourcegroupstaggingapi get-resources \
    --resource-type-filters "$res_type" \
    --tag-filters "${tag_filters_rgt[@]}" \
    --query 'ResourceTagMappingList[].ResourceARN' --output text 2>/dev/null | tr '\t' '\n' | sed '/^$/d' || true
}

# Build EC2 filters array based on PREFIX/tags
ec2_filters_common=()
if [[ -n "$PREFIX" ]]; then
  ec2_filters_common+=( "Name=tag:Name,Values=${PREFIX}*" )
fi
[[ -n "$TAG_PROJECT"    ]] && ec2_filters_common+=( "Name=tag:Project,Values=${TAG_PROJECT}" )
[[ -n "$TAG_ENV"        ]] && ec2_filters_common+=( "Name=tag:Environment,Values=${TAG_ENV}" )
[[ -n "$TAG_MANAGED_BY" ]] && ec2_filters_common+=( "Name=tag:ManagedBy,Values=${TAG_MANAGED_BY}" )

# ---------- Discover ----------
title "Discovery ($AWS_REGION)"

# ALBs/TGs (by prefix or tags)
ALB_ARNS=()
if [[ -n "$PREFIX" ]]; then
  while read -r arn name; do
    [[ -z "${name:-}" ]] && continue
    [[ "$name" == "$PREFIX"-* ]] && ALB_ARNS+=("$arn")
  done < <(aws elbv2 describe-load-balancers \
    --query 'LoadBalancers[].{ARN:LoadBalancerArn,Name:LoadBalancerName}' \
    --output text 2>/dev/null)
else
  while read -r arn; do [[ -n "$arn" ]] && ALB_ARNS+=("$arn"); done < <(get_tagged_arns "elasticloadbalancing:loadbalancer")
fi

# Target groups attached to those ALBs + by prefix
TG_ARNS=()
for alb in "${ALB_ARNS[@]}"; do
  while read -r tg; do [[ -n "$tg" ]] && TG_ARNS+=("$tg"); done < <(
    aws elbv2 describe-target-groups --load-balancer-arn "$alb" \
      --query 'TargetGroups[].TargetGroupArn' --output text 2>/dev/null | tr '\t' '\n'
  )
done
if [[ -n "$PREFIX" ]]; then
  while read -r tg tgname; do
    [[ -n "${tgname:-}" && "$tgname" == "$PREFIX"-* ]] && TG_ARNS+=("$tg")
  done < <(aws elbv2 describe-target-groups \
    --query 'TargetGroups[].{ARN:TargetGroupArn,Name:TargetGroupName}' \
    --output text 2>/dev/null)
fi
if ((${#TG_ARNS[@]})); then
  TG_ARNS=($(printf '%s\n' "${TG_ARNS[@]}" | awk '!seen[$0]++'))
fi

# EFS via creation-token + tags
EFS_IDS=()
if [[ -n "$PREFIX" ]]; then
  tmp_id="$(aws efs describe-file-systems --creation-token "${PREFIX}-efs" \
           --query 'FileSystems[0].FileSystemId' --output text 2>/dev/null || true)"
  [[ -n "$tmp_id" && "$tmp_id" != "None" ]] && EFS_IDS+=("$tmp_id")
fi
while read -r arn; do
  [[ -z "${arn:-}" ]] && continue
  fsid="${arn##*/}"
  [[ -n "$fsid" ]] && EFS_IDS+=("$fsid")
done < <(get_tagged_arns "efs:file-system")
if ((${#EFS_IDS[@]})); then
  EFS_IDS=($(printf '%s\n' "${EFS_IDS[@]}" | awk '!seen[$0]++'))
fi

# Secrets via name + tags
SECRETS=()
if [[ -n "$PREFIX" ]]; then
  tmp_sec="$(aws secretsmanager describe-secret --secret-id "${PREFIX}/rds/postgres" \
            --query 'ARN' --output text 2>/dev/null || true)"
  [[ -n "$tmp_sec" && "$tmp_sec" != "None" ]] && SECRETS+=("$tmp_sec")
fi
while read -r arn; do [[ -n "$arn" ]] && SECRETS+=("$arn"); done < <(get_tagged_arns "secretsmanager:secret")
if ((${#SECRETS[@]})); then
  SECRETS=($(printf '%s\n' "${SECRETS[@]}" | awk '!seen[$0]++'))
fi

# RDS groups
DB_SUBNET_GROUPS=()
DB_PARAM_GROUPS=()
if [[ -n "$PREFIX" ]]; then
  sg="${PREFIX}-db-subnets"; pg="${PREFIX}-pg"
  aws rds describe-db-subnet-groups --db-subnet-group-name "$sg" >/dev/null 2>&1 && DB_SUBNET_GROUPS+=("$sg") || true
  aws rds describe-db-parameter-groups --db-parameter-group-name "$pg" >/dev/null 2>&1 && DB_PARAM_GROUPS+=("$pg") || true
fi

# IAM (prefix)
IAM_ROLES=(); IAM_POLICIES=(); IAM_PROFILES=()
if [[ -n "$PREFIX" ]]; then
  while read -r rn;  do [[ "$rn"  == "$PREFIX"-* ]] && IAM_ROLES+=("$rn");    done < <(aws iam list-roles --query 'Roles[].RoleName' --output text 2>/dev/null | tr '\t' '\n')
  while read -r pn;  do [[ "$pn"  == "$PREFIX"-* ]] && IAM_POLICIES+=("$pn");  done < <(aws iam list-policies --scope Local --query 'Policies[].PolicyName' --output text 2>/dev/null | tr '\t' '\n')
  while read -r ipn; do [[ "$ipn" == "$PREFIX"-* ]] && IAM_PROFILES+=("$ipn"); done < <(aws iam list-instance-profiles --query 'InstanceProfiles[].InstanceProfileName' --output text 2>/dev/null | tr '\t' '\n')
fi

# ---------- Discover VPC stack (opt-in) ----------
VPC_IDS=()
if [[ "$DELETE_VPC_STACK" == "true" ]]; then
  if ((${#ec2_filters_common[@]})); then
    # shellcheck disable=SC2207
    VPC_IDS=($(aws ec2 describe-vpcs \
      --filters "${ec2_filters_common[@]}" \
      --query 'Vpcs[].VpcId' --output text 2>/dev/null | tr '\t' '\n'))
  fi
fi

# ---- Show plan ----
title "Will attempt to delete (discovered):"
say "ALBs:        ${#ALB_ARNS[@]}";  printf '  %s\n' "${ALB_ARNS[@]:-}"
say "TargetGroups:${#TG_ARNS[@]}";  printf '  %s\n' "${TG_ARNS[@]:-}"
say "EFS:         ${#EFS_IDS[@]}";  printf '  %s\n' "${EFS_IDS[@]:-}"
say "Secrets:     ${#SECRETS[@]}";  printf '  %s\n' "${SECRETS[@]:-}"
say "DB Subnets:  ${#DB_SUBNET_GROUPS[@]}"; printf '  %s\n' "${DB_SUBNET_GROUPS[@]:-}"
say "DB Params:   ${#DB_PARAM_GROUPS[@]}";  printf '  %s\n' "${DB_PARAM_GROUPS[@]:-}"
say "IAM Roles:   ${#IAM_ROLES[@]}";        printf '  %s\n' "${IAM_ROLES[@]:-}"
say "IAM Policies:${#IAM_POLICIES[@]}";     printf '  %s\n' "${IAM_POLICIES[@]:-}"
say "IAM Profiles:${#IAM_PROFILES[@]}";     printf '  %s\n' "${IAM_PROFILES[@]:-}"
say "VPCs:        ${#VPC_IDS[@]} (DELETE_VPC_STACK=${DELETE_VPC_STACK})"; printf '  %s\n' "${VPC_IDS[@]:-}"
say "ENI cleanup: DELETE_ENIS=${DELETE_ENIS}, EIP release: ${DELETE_EIPS}, DRY_RUN=${DRY_RUN}"

confirm "Proceed to delete these? " || { say "Aborted."; exit 0; }

# --------- Delete in safe order ---------
title "Deleting ALB stack"
if [[ "${DELETE_ALB}" == "true" ]]; then
  for alb in "${ALB_ARNS[@]:-}"; do
    while read -r lst; do
      [[ -n "$lst" ]] && do_aws elbv2 delete-listener --listener-arn "$lst" || true
    done < <(aws elbv2 describe-listeners --load-balancer-arn "$alb" \
          --query 'Listeners[].ListenerArn' --output text 2>/dev/null | tr '\t' '\n')
    do_aws elbv2 delete-load-balancer --load-balancer-arn "$alb" || true
  done
  for tg in "${TG_ARNS[@]:-}"; do
    do_aws elbv2 delete-target-group --target-group-arn "$tg" || true
  done
else
  say "DELETE_ALB=false — skipping ALB/TG deletion"
fi

title "Deleting EFS"
for fs in "${EFS_IDS[@]:-}"; do
  mts=$(aws efs describe-mount-targets --file-system-id "$fs" --query 'MountTargets[].MountTargetId' --output text 2>/dev/null | tr '\t' '\n')
  for mt in $mts; do do_aws efs delete-mount-target --mount-target-id "$mt" || true; done
  for _ in {1..10}; do
    left=$(aws efs describe-mount-targets --file-system-id "$fs" --query 'length(MountTargets)' --output text 2>/dev/null || echo 0)
    [[ "$left" == "0" ]] && break
    sleep 5
  done
  do_aws efs delete-file-system --file-system-id "$fs" || true
done

title "Deleting Secrets"
for s in "${SECRETS[@]:-}"; do
  do_aws secretsmanager delete-secret --secret-id "$s" --force-delete-without-recovery || true
done

title "Deleting RDS groups"
for g in "${DB_SUBNET_GROUPS[@]:-}"; do do_aws rds delete-db-subnet-group --db-subnet-group-name "$g" || true; done
for g in "${DB_PARAM_GROUPS[@]:-}";  do
  inuse=$(aws rds describe-db-instances --query "DBInstances[?DBParameterGroups[?DBParameterGroupName=='$g']].DBInstanceIdentifier" --output text 2>/dev/null)
  [[ -z "$inuse" ]] && do_aws rds delete-db-parameter-group --db-parameter-group-name "$g" || true
done

if [[ "$DELETE_RDS_INSTANCE" == "true" && -n "${DB_INSTANCE_IDENTIFIER:-}" ]]; then
  title "Deleting RDS instance: $DB_INSTANCE_IDENTIFIER"
  do_aws rds delete-db-instance --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" \
    --skip-final-snapshot --delete-automated-backups || true
  if [[ "$DRY_RUN" != "true" ]]; then
    aws rds wait db-instance-deleted --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" >/dev/null 2>&1 || true
  fi
fi

title "Deleting IAM instance profiles"
for ip in "${IAM_PROFILES[@]:-}"; do
  roles=$(aws iam get-instance-profile --instance-profile-name "$ip" --query 'InstanceProfile.Roles[].RoleName' --output text 2>/dev/null | tr '\t' '\n')
  for r in $roles; do do_aws iam remove-role-from-instance-profile --instance-profile-name "$ip" --role-name "$r" || true; done
  do_aws iam delete-instance-profile --instance-profile-name "$ip" || true
done

title "Deleting IAM policies"
for pn in "${IAM_POLICIES[@]:-}"; do
  arn=$(aws iam list-policies --scope Local --query "Policies[?PolicyName=='$pn'].Arn" --output text 2>/dev/null | head -n1)
  [[ -z "$arn" ]] && continue
  roles=$(aws iam list-entities-for-policy --policy-arn "$arn" --query 'PolicyRoles[].RoleName' --output text 2>/dev/null | tr '\t' '\n')
  for r in $roles; do do_aws iam detach-role-policy --role-name "$r" --policy-arn "$arn" || true; done
  vers=$(aws iam list-policy-versions --policy-arn "$arn" --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text 2>/dev/null | tr '\t' '\n')
  for v in $vers; do do_aws iam delete-policy-version --policy-arn "$arn" --version-id "$v" || true; done
  do_aws iam delete-policy --policy-arn "$arn" || true
done

title "Deleting IAM roles"
for rn in "${IAM_ROLES[@]:-}"; do
  for a in $(aws iam list-attached-role-policies --role-name "$rn" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null | tr '\t' '\n'); do
    do_aws iam detach-role-policy --role-name "$rn" --policy-arn "$a" || true
  done
  for p in $(aws iam list-role-policies --role-name "$rn" --query 'PolicyNames[]' --output text 2>/dev/null | tr '\t' '\n'); do
    do_aws iam delete-role-policy --role-name "$rn" --policy-name "$p" || true
  done
  do_aws iam delete-role --role-name "$rn" || true
done

# --------- VPC stack teardown (opt-in) ---------
if [[ "$DELETE_VPC_STACK" == "true" && ${#VPC_IDS[@]} -gt 0 ]]; then
  title "Tearing down VPC stack(s)"
  for vpc in "${VPC_IDS[@]}"; do
    say "VPC: $vpc"

    # Endpoints (interface & gateway)
    eps=$(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=${vpc}" --query 'VpcEndpoints[].VpcEndpointId' --output text 2>/dev/null | tr '\t' '\n')
    for ep in $eps; do do_aws ec2 delete-vpc-endpoints --vpc-endpoint-ids "$ep" || true; done

    # NAT Gateways (and collect EIPs)
    natgws=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=${vpc}" --query 'NatGateways[].NatGatewayId' --output text 2>/dev/null | tr '\t' '\n')
    nat_eips=()
    for ng in $natgws; do
      while read -r alloc; do [[ -n "$alloc" ]] && nat_eips+=("$alloc"); done < <(
        aws ec2 describe-nat-gateways --nat-gateway-ids "$ng" \
        --query 'NatGateways[].NatGatewayAddresses[].AllocationId' --output text 2>/dev/null | tr '\t' '\n'
      )
      do_aws ec2 delete-nat-gateway --nat-gateway-id "$ng" || true
    done
    if [[ "$DRY_RUN" != "true" && -n "${natgws:-}" ]]; then
      say "Waiting for NAT gateways to delete..."
      for _ in {1..30}; do
        left=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=${vpc}" --query "length(NatGateways[?State!='deleted'])" --output text 2>/dev/null || echo 0)
        [[ "$left" == "0" ]] && break
        sleep 10
      done
    fi
    if [[ "$DELETE_EIPS" == "true" && ${#nat_eips[@]} -gt 0 ]]; then
      for a in "${nat_eips[@]}"; do do_aws ec2 release-address --allocation-id "$a" || true; done
    fi

    # Route Tables: remove non-local routes; delete non-main RTs
    rtb_ids=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=${vpc}" --query 'RouteTables[].RouteTableId' --output text 2>/dev/null | tr '\t' '\n')
    main_rtb=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=${vpc}" \
              --query 'RouteTables[?Associations[?Main==`true`]].RouteTableId' --output text 2>/dev/null | tr '\t' '\n' | head -n1)
    for rtb in $rtb_ids; do
      assoc_ids=$(aws ec2 describe-route-tables --route-table-ids "$rtb" \
                  --query 'RouteTables[].Associations[?Main==`false`].RouteTableAssociationId' --output text 2>/dev/null | tr '\t' '\n')
      for a in $assoc_ids; do do_aws ec2 disassociate-route-table --association-id "$a" || true; done
      cidrs=$(aws ec2 describe-route-tables --route-table-ids "$rtb" \
              --query 'RouteTables[].Routes[?GatewayId!=`local` && !not_null(NatGatewayId) && !not_null(VpcPeeringConnectionId) && !not_null(TransitGatewayId)].DestinationCidrBlock' \
              --output text 2>/dev/null | tr '\t' '\n')
      for dst in $cidrs; do do_aws ec2 delete-route --route-table-id "$rtb" --destination-cidr-block "$dst" || true; done
      plids=$(aws ec2 describe-route-tables --route-table-ids "$rtb" \
              --query 'RouteTables[].Routes[?not_null(DestinationPrefixListId)].DestinationPrefixListId' \
              --output text 2>/dev/null | tr '\t' '\n')
      for pl in $plids; do do_aws ec2 delete-route --route-table-id "$rtb" --destination-prefix-list-id "$pl" || true; done
      if [[ "$rtb" != "$main_rtb" ]]; then
        do_aws ec2 delete-route-table --route-table-id "$rtb" || true
      fi
    done

    # Internet Gateways
    igws=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=${vpc}" --query 'InternetGateways[].InternetGatewayId' --output text 2>/dev/null | tr '\t' '\n')
    for igw in $igws; do
      do_aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$vpc" || true
      do_aws ec2 delete-internet-gateway --internet-gateway-id "$igw" || true
    done

    # Subnets
    subnets=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${vpc}" --query 'Subnets[].SubnetId' --output text 2>/dev/null | tr '\t' '\n')
    for sn in $subnets; do
      do_aws ec2 delete-subnet --subnet-id "$sn" || true
    done

    # Security Groups (non-default)
    sgs=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${vpc}" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null | tr '\t' '\n')
    for sg in $sgs; do do_aws ec2 delete-security-group --group-id "$sg" || true; done

    # Stray ENIs (available only)
    if [[ "$DELETE_ENIS" == "true" ]]; then
      enis=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=${vpc}" "Name=status,Values=available" \
              --query 'NetworkInterfaces[].NetworkInterfaceId' --output text 2>/dev/null | tr '\t' '\n')
      for eni in $enis; do do_aws ec2 delete-network-interface --network-interface-id "$eni" || true; done
    fi

    # Finally: VPC
    do_aws ec2 delete-vpc --vpc-id "$vpc" || true
  done
fi

title "Done ✅"
say "Note: DRY_RUN=${DRY_RUN}. Set DRY_RUN=false to actually delete."
