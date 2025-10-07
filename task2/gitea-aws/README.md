# Task 2 – Infrastructure Automation Setup (DIGITALL / SAP SRE Demo)

[![Terraform](https://img.shields.io/badge/Terraform-v1.9+-blue)]()
[![AWS](https://img.shields.io/badge/Cloud-AWS-orange)]()
[![CI/CD](https://img.shields.io/github/actions/workflow/status/birkoff88/sap_tasks/terraform-task2.yml?label=CI%2FCD)]()

This project demonstrates automated provisioning of a **web-application stack on AWS** using Terraform and Bash automation scripts.  
It fulfills the Task 2 requirements from the *Site Reliability Engineer – Technical Interview Tasks*.

---

## 🧩 Architecture Overview
| Component | Service | Purpose |
|------------|----------|----------|
| **Load Balancer** | AWS Application Load Balancer | Exposes the web app publicly, handles health checks |
| **Web App Servers** | AWS EC2 Auto Scaling Group (t3.small) | Runs Gitea (web UI + API) |
| **Persistent Storage** | AWS EFS | Stores Gitea repositories and uploaded data |
| **Database** | AWS RDS (PostgreSQL 16.x) | Persists configuration + user data |
| **Monitoring / Observability** | AWS CloudWatch (default metrics) | Basic health and logs |
| **IaC Automation** | Terraform + Bash scripts | Declarative and repeatable infrastructure |

---

## 🛠️ Tools and Technologies
- **Terraform v1.9+**
- **AWS** – EC2, ALB, EFS, RDS
- **Amazon Linux 2023**
- **GitHub Actions**
- **Bash scripts** – setup, cleanup, user-data, Makefile

---

## ⚙️ Repository Structure
```
task2/gitea-aws/
├── .tflint.hcl
├── ARCHITECTURE.md
├── CI_CD.md
├── README.md
├── docs/
│   └── failover.md
├── main.tf
├── outputs.tf
├── user-data.sh
├── variables.tf
└── scripts/
    ├── cleanup.sh
    ├── Makefile
    └── setup.sh
```

---

## 🚀 Usage

### Prerequisites
- Terraform ≥ 1.9  
- AWS account (free tier OK)  
- IAM role with EC2, EFS, RDS, ALB permissions  
- AWS CLI configured or GitHub OIDC role (`AWS_ROLE_ARN` secret)

### Quick start (Local or Actions Runner)
```bash
git clone https://github.com/birkoff88/sap_tasks.git
cd task2/gitea-aws
chmod +x scripts/*.sh
./scripts/setup.sh
terraform init
terraform plan
terraform apply -auto-approve
```

Outputs include:
```
alb_dns_name = <your-lb-dns>
rds_endpoint = <db-endpoint>
```
Open `http://<alb_dns_name>:80` to access Gitea.

---

## 🧹 Teardown
```bash
terraform destroy -auto-approve
./scripts/cleanup.sh
```

---

## 🧠 Design Highlights
- Fully automated provisioning
- Idempotent configuration via Terraform state
- Secure defaults (IMDSv2, encryption, private subnets)
- CI/CD pipeline (`terraform-task2.yml`)
- Scalable and extendable

---

## 🧾 Optional Enhancements
| Category | Idea |
|-----------|------|
| **Fail-over** | Auto Scaling Group across AZs; ALB health checks |
| **Secrets Management** | AWS Secrets Manager for DB creds |
| **Remote Backend** | S3 + DynamoDB for state |
| **Monitoring** | Prometheus / Grafana integration |
| **TLS** | ACM certificates for HTTPS |

---

## 🧩 Related Work
- **Task 1 – Certificate Expiry Checker**  
  `task1/ssl_checker` – Python-based certificate monitoring with optional Slack alerts.

---

## 📄 License
MIT License – Demo purposes only.
