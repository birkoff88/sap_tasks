#!/usr/bin/env bash
# Idempotent cleanup for Gitea demo infra (quiet, professional output)
# - Checks existence before deletes
# - Suppresses AWS CLI error spew for already-gone resources
# - Prints [OK]/[SKIP]/[WARN] lines only
# - Optional: delete RDS instance and/or ALB stack (off by default)

set -uo pipefail

# -------------------- CONFIG --------------------
export AWS_REGION="${AWS_REGION:-eu-central-1}"
export AWS_DEFAULT_REGION="$AWS_REGION"

EFS_ID="fs-05615f127860e073b"
SECRET_NAME="gitea-demo/rds/postgres"
DB_SUBNET_GRP="gitea-demo-db-subnets"
DB_PARAM_GRP="gitea-demo-pg"
ROLE_EM="gitea-demo-rds-em"
ROLE_EC2="gitea-demo-ec2-role"
IPROFILE_EC2="gitea-demo-ec2-profile"
POLICY_KMS_DECRYPT_NAME="gitea-demo-secrets-kms-decrypt"

# Optional toggles (set to "true" if you *also* want to delete these)
DELETE_RDS_INSTANCE="${DELETE_RDS_INSTANCE:-false}"
DB_INSTANCE_IDENTIFIER="${DB_INSTANCE_IDENTIFIER:-gitea-demo-postgres}"

DELETE_ALB_STACK="${DELETE_ALB_STACK:-false}"
ALB_NAME="${ALB_NAME:-gitea-demo-alb}"
# ------------------------------------------------

# ---------- tiny logger helpers ----------
ts() { date -Is | cut -c1-19; }
log()  { printf '%s [INFO] %s\n' "$(ts)" "$*"; }
ok()   { printf '%s [OK]   %s\n' "$(ts)" "$*"; }
skip() { printf '%s [SKIP] %s\n' "$(ts)" "$*"; }
warn() { printf '%s [WARN] %s\n' "$(ts)" "$*"; }
err()  { printf '%s [ERR]  %s\n' "$(ts)" "$*"; }
# ----------------------------------------

log "Region: $AWS_REGION"
read -r -p "Proceed with cleanup in $AWS_REGION? [y/N] " ans
[[ "$ans" =~ ^[yY]$ ]] || { log "Aborted."; exit 0; }

# =============== EFS ==================
delete_efs() {
  local fs_id="$1"
  # Does FS exist?
  if ! aws efs describe-file-systems --file-system-id "$fs_id" >/dev/null 2>&1; then
    skip "EFS $fs_id already deleted"
    return 0
  fi

  # Delete mount targets first
  MT_IDS=$(aws efs describe-mount-targets --file-system-id "$fs_id" \
            --query 'MountTargets[].MountTargetId' --output text 2>/dev/null | tr '\t' '\n')
  if [ -n "${MT_IDS:-}" ]; then
    log "EFS $fs_id: deleting mount targets…"
    for mt in $MT_IDS; do
      aws efs delete-mount-target --mount-target-id "$mt" >/dev/null 2>&1 || true
    done
    # Wait until none remain
    for _ in $(seq 1 30); do
      CUR=$(aws efs describe-mount-targets --file-system-id "$fs_id" \
            --query 'MountTargets' --output json 2>/dev/null || echo "[]")
      [ "$CUR" = "[]" ] && break
      sleep 5
    done
  fi

  # Delete FS
  aws efs delete-file-system --file-system-id "$fs_id" >/dev/null 2>&1 || true
  # Wait gone
  for _ in $(seq 1 30); do
    if ! aws efs describe-file-systems --file-system-id "$fs_id" >/dev/null 2>&1; then
      ok "EFS $fs_id deleted"
      return 0
    fi
    sleep 5
  done
  warn "EFS $fs_id deletion still in progress"
}

# ============ Secrets Manager =========
delete_secret() {
  local name="$1"
  if ! aws secretsmanager describe-secret --secret-id "$name" >/dev/null 2>&1; then
    skip "Secret '$name' already deleted"
    return 0
  fi
  aws secretsmanager delete-secret --secret-id "$name" --force-delete-without-recovery >/dev/null 2>&1 || true
  ok "Secret '$name' deleted (forced)"
}

# ================ RDS =================
delete_db_subnet_group() {
  local grp="$1"
  if ! aws rds describe-db-subnet-groups --db-subnet-group-name "$grp" >/dev/null 2>&1; then
    skip "DB Subnet Group '$grp' already deleted"
    return 0
  fi
  aws rds delete-db-subnet-group --db-subnet-group-name "$grp" >/dev/null 2>&1 || true
  ok "DB Subnet Group '$grp' deleted"
}

delete_db_param_group() {
  local grp="$1"
  if ! aws rds describe-db-parameter-groups --db-parameter-group-name "$grp" >/dev/null 2>&1; then
    skip "DB Parameter Group '$grp' already deleted"
    return 0
  fi
  USING_DBS=$(aws rds describe-db-instances \
    --query "DBInstances[?DBParameterGroups[?DBParameterGroupName=='$grp']].DBInstanceIdentifier" \
    --output text 2>/dev/null | tr '\t' '\n')
  if [ -n "${USING_DBS:-}" ]; then
    warn "Parameter group '$grp' in use by: $USING_DBS (skip delete)"
    return 0
  fi
  aws rds delete-db-parameter-group --db-parameter-group-name "$grp" >/dev/null 2>&1 || true
  ok "DB Parameter Group '$grp' deleted"
}

delete_rds_instance_optional() {
  local id="$1"
  [ "${DELETE_RDS_INSTANCE}" != "true" ] && return 0
  if ! aws rds describe-db-instances --db-instance-identifier "$id" >/dev/null 2>&1; then
    skip "RDS instance '$id' already deleted"
    return 0
  fi
  log "Deleting RDS instance '$id' (no final snapshot)…"
  aws rds delete-db-instance --db-instance-identifier "$id" \
      --skip-final-snapshot --delete-automated-backups >/dev/null 2>&1 || true
  aws rds wait db-instance-deleted --db-instance-identifier "$id" >/dev/null 2>&1 || true
  ok "RDS instance '$id' deleted"
}

# ================ IAM =================
cleanup_instance_profile() {
  local prof="$1"
  if ! aws iam get-instance-profile --instance-profile-name "$prof" >/dev/null 2>&1; then
    skip "Instance profile '$prof' already deleted"
    return 0
  fi
  ROLES=$(aws iam get-instance-profile --instance-profile-name "$prof" \
          --query 'InstanceProfile.Roles[].RoleName' --output text 2>/dev/null | tr '\t' '\n')
  for r in $ROLES; do
    aws iam remove-role-from-instance-profile --instance-profile-name "$prof" --role-name "$r" >/dev/null 2>&1 || true
  done
  aws iam delete-instance-profile --instance-profile-name "$prof" >/dev/null 2>&1 || true
  ok "Instance profile '$prof' deleted"
}

cleanup_role() {
  local role="$1"
  if ! aws iam get-role --role-name "$role" >/dev/null 2>&1; then
    skip "Role '$role' already deleted"
    return 0
  fi
  # Detach managed policies
  ARNS=$(aws iam list-attached-role-policies --role-name "$role" \
         --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null | tr '\t' '\n')
  for a in $ARNS; do
    [ -n "$a" ] && aws iam detach-role-policy --role-name "$role" --policy-arn "$a" >/dev/null 2>&1 || true
  done
  # Delete inline policies
  INLINES=$(aws iam list-role-policies --role-name "$role" \
           --query 'PolicyNames[]' --output text 2>/dev/null | tr '\t' '\n')
  for p in $INLINES; do
    [ -n "$p" ] && aws iam delete-role-policy --role-name "$role" --policy-name "$p" >/dev/null 2>&1 || true
  done
  # Delete the role
  aws iam delete-role --role-name "$role" >/dev/null 2>&1 || true
  ok "Role '$role' deleted"
}

delete_customer_policy_by_name() {
  local pname="$1"
  POL_ARN=$(aws iam list-policies --scope Local \
    --query "Policies[?PolicyName=='$pname'].Arn" --output text 2>/dev/null | tr '\t' '\n' | head -n1)
  if [ -z "${POL_ARN:-}" ]; then
    skip "Policy '$pname' already deleted"
    return 0
  fi
  # Detach from roles
  ATTACH_ROLES=$(aws iam list-entities-for-policy --policy-arn "$POL_ARN" \
    --query 'PolicyRoles[].RoleName' --output text 2>/dev/null | tr '\t' '\n')
  for r in $ATTACH_ROLES; do
    aws iam detach-role-policy --role-name "$r" --policy-arn "$POL_ARN" >/dev/null 2>&1 || true
  done
  # Delete non-default versions
  VERS=$(aws iam list-policy-versions --policy-arn "$POL_ARN" \
    --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text 2>/dev/null | tr '\t' '\n')
  for v in $VERS; do
    aws iam delete-policy-version --policy-arn "$POL_ARN" --version-id "$v" >/dev/null 2>&1 || true
  done
  # Delete policy
  aws iam delete-policy --policy-arn "$POL_ARN" >/dev/null 2>&1 || true
  ok "Policy '$pname' deleted"
}

# ================ ALB =================
delete_alb_stack_optional() {
  [ "${DELETE_ALB_STACK}" != "true" ] && return 0
  local name="$1"
  ALB_ARN=$(aws elbv2 describe-load-balancers --names "$name" \
             --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || true)
  if [ -z "${ALB_ARN:-}" ] || [ "$ALB_ARN" = "None" ]; then
    skip "ALB '$name' already deleted"
    return 0
  fi
  # Listeners
  LST=$(aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" \
        --query 'Listeners[].ListenerArn' --output text 2>/dev/null | tr '\t' '\n')
  for l in $LST; do aws elbv2 delete-listener --listener-arn "$l" >/dev/null 2>&1 || true; done
  # Target groups for this ALB
  TGS=$(aws elbv2 describe-target-groups --load-balancer-arn "$ALB_ARN" \
        --query 'TargetGroups[].TargetGroupArn' --output text 2>/dev/null | tr '\t' '\n')
  # Delete LB
  aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN" >/dev/null 2>&1 || true
  # Wait a bit then delete TGs
  sleep 5
  for tg in $TGS; do aws elbv2 delete-target-group --target-group-arn "$tg" >/dev/null 2>&1 || true; done
  ok "ALB '$name' (and related listeners/TGs) deleted"
}

# --------------- RUN -------------------
log "Starting cleanup…"

delete_efs "$EFS_ID"
delete_secret "$SECRET_NAME"
delete_db_subnet_group "$DB_SUBNET_GRP"
delete_db_param_group "$DB_PARAM_GRP"
delete_rds_instance_optional "$DB_INSTANCE_IDENTIFIER"

cleanup_instance_profile "$IPROFILE_EC2"
cleanup_role "$ROLE_EM"
cleanup_role "$ROLE_EC2"
delete_customer_policy_by_name "$POLICY_KMS_DECRYPT_NAME"

delete_alb_stack_optional "$ALB_NAME"

ok "Cleanup finished."
