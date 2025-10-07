# DIGITALL / SAP – Site Reliability Engineer Technical Tasks

[![Terraform](https://img.shields.io/badge/Terraform-v1.9+-blue)]()
[![AWS](https://img.shields.io/badge/Cloud-AWS-orange)]()
[![CI/CD](https://img.shields.io/github/actions/workflow/status/birkoff88/sap_tasks/terraform-task2.yml?label=Terraform%20CI%2FCD)](https://github.com/birkoff88/sap_tasks/actions/workflows/terraform-task2.yml)

This repository contains my completed **Site Reliability Engineer (SRE)** technical assessment for **DIGITALL / SAP**, demonstrating both software automation and infrastructure-as-code capabilities.

The repo is structured into two self-contained tasks:

---

## 🧩 Task 1 – SSL/TLS Certificate Expiry Checker
**Tech:** Python 3  |  Docker  
**Folder:** [`task1/`](task1)

A containerized Python utility that:
- Checks SSL/TLS certificate expiration for multiple domains.  
- Supports configurable warning/critical thresholds via `config.json`.  
- Optionally sends Slack notifications for expiring certificates.  
- Includes Docker packaging for local or CI execution.

**Purpose:** Demonstrates scripting, containerization, and lightweight monitoring logic.

---

## ⚙️ Task 2 – AWS Infrastructure Automation (Gitea Stack)
**Tech:** Terraform  |  AWS  |  GitHub Actions  |  Bash  
**Folder:** [`task2/gitea-aws/`](task2/gitea-aws)

Implements a fully automated deployment of a web-application stack on AWS:

| Component | AWS Service | Purpose |
|------------|-------------|----------|
| **Load Balancer** | ALB | Public entry point + health checks |
| **Web App Servers** | EC2 (ASG) | Run Gitea web UI + API |
| **Database** | RDS (PostgreSQL 16.x) | Persistent backend storage |
| **Shared Storage** | EFS | Persist Gitea repos/data across instances |
| **CI/CD** | GitHub Actions | Lint → Validate → Plan → Apply |
| **Failover** | ALB + ASG + EFS | Self-healing + multi-AZ resilience |

Includes:
- `main.tf`, `variables.tf`, `outputs.tf`, and `.tflint.hcl` (for validation and best-practice linting).  
- Automated provisioning with `setup.sh` and `cleanup.sh`.  
- Documentation: [`ARCHITECTURE.md`](task2/gitea-aws/ARCHITECTURE.md), [`CI_CD.md`](task2/gitea-aws/CI_CD.md), [`docs/failover.md`](task2/gitea-aws/docs/failover.md).  
- Root-level CI/CD workflow: [`.github/workflows/terraform-task2.yml`](.github/workflows/terraform-task2.yml).

**Purpose:** Demonstrates professional IaC patterns — idempotent Terraform code, secure AWS architecture, and CI/CD pipeline integration.

---

## 📦 Repository Structure
```
sap_tasks/
├── task1/ssl_checker/
│   ├── cert_checker.py
│   ├── config.json
│   ├── Dockerfile
│   └── README.md
└── task2/gitea-aws/
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    ├── user-data.sh
    ├── scripts/
    ├── docs/
    └── .tflint.hcl
```

---

## 🧠 Highlights
- Declarative IaC using **Terraform** with AWS provider.  
- GitHub OIDC authentication (no static keys).  
- Automated formatting, validation, and linting (`tflint`).  
- Scalable and self-healing EC2 Auto Scaling Group.  
- Persistent EFS volume for application data.  
- Clean project structure with documentation and CI/CD workflow.

---

## 🧰 Usage Notes
1. Clone the repository.  
2. For Task 1, build and run the Docker image locally or in CI.  
3. For Task 2, run:
   ```bash
   cd task2/gitea-aws
   terraform init
   terraform plan
   terraform apply -auto-approve
   ```
4. View Terraform outputs for the ALB DNS and RDS endpoint.

---

## 🪄 CI/CD Workflow
- Defined in [`.github/workflows/terraform-task2.yml`](.github/workflows/terraform-task2.yml).  
- Runs on every PR or push affecting `task2/gitea-aws/**`.  
- Steps: `fmt` → `validate` → `tflint` → `plan` (+ optional manual `apply`).  
- Uses **GitHub OIDC** to assume an AWS IAM role securely.

---

## 📜 License
Licensed under the **MIT License** © 2025 Boris Petrov.  
See the [LICENSE](LICENSE) file for details.
