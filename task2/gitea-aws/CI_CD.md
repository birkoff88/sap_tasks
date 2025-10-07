# CI/CD Pipeline – Terraform Task 2

The pipeline (`.github/workflows/terraform-task2.yml`) implements a production-style CI/CD pattern.

| Stage | Description |
|--------|--------------|
| **Plan** | Triggered on PRs to `main`. Runs `fmt`, `validate`, `tflint`, `checkov`, posts Terraform plan as PR comment. |
| **Apply** | Manual trigger (`workflow_dispatch`) or push with `apply=true`. Applies plan via OIDC role. |
| **OIDC Auth** | GitHub → AWS federation (no static keys). |
| **Artifacts** | Stores compiled `tfplan` for reuse. |
| **Concurrency** | Cancels stale runs automatically. |

**Secrets required:**
- `AWS_ROLE_ARN` – IAM role ARN for OIDC access.  
- (Optional) `STATE_BUCKET`, `LOCK_TABLE` – for remote backend.

