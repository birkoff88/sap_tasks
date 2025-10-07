# Failover and Self-Healing – Implemented Mechanisms

This environment demonstrates multiple levels of failover and self-healing behavior built into the AWS infrastructure.

---

## 1️⃣ Load Balancer (Traffic-Level Failover)

- The **Application Load Balancer (ALB)** automatically performs health checks on all EC2 targets.
- When a target (EC2 instance) becomes **unhealthy**, the ALB **stops routing traffic** to it immediately.
- This ensures that user requests are always served by healthy nodes.

**Demo step:**
```bash
sudo systemctl stop gitea
```
Within seconds, ALB marks the instance unhealthy, removes it from rotation, and traffic continues via the remaining healthy node(s).

---

## 2️⃣ Auto Scaling Group (Instance-Level Failover)

- The **Auto Scaling Group (ASG)** uses ELB health checks (`health_check_type = "ELB"`).
- When an instance stays unhealthy beyond the grace period, the ASG **terminates it and launches a new one** automatically.
- The new instance mounts EFS and re-registers with the ALB once healthy.

Result: **automatic service recovery** without manual intervention.

---

## 3️⃣ EFS Storage (Data Continuity Across Failover)

- Application data is stored in **Amazon EFS**, mounted at `/data/gitea`.
- With mount targets in each AZ, replacement instances **reuse the same persistent storage** after failover.
- Repositories and configuration remain intact across node replacements.

---

## 4️⃣ Multi-AZ Design (Availability Zone Failover)

- The ASG spans **multiple subnets across different AZs**.
- The ALB routes traffic only to healthy targets in healthy AZs.
- If an AZ or subnet fails, requests automatically shift to instances in the other AZ.

---

## 5️⃣ Optional Database Failover (future-ready)

- Currently RDS runs in single-AZ for cost optimization.
- Enabling `multi_az = true` provides **automated database failover** managed by AWS.
- This is a one-line Terraform change when needed.

---

## 6️⃣ Verification Steps (for live demo)

1. Connect to one app instance (SSM/SSH) and stop the app:  
   ```bash
   sudo systemctl stop gitea
   ```
2. Observe **Target Group** in the ALB: the target becomes **unhealthy**.
3. Observe **ASG**: the unhealthy instance is **replaced automatically**.
4. After 1–2 minutes the new instance registers **healthy** and traffic resumes normally.
5. Confirm your data persists (shared **EFS**).

---

## ✅ Summary

| Layer    | Service     | Failover Type                            | Automated? |
|---------:|-------------|-------------------------------------------|------------|
| Traffic  | ALB         | Route-away from unhealthy targets         | ✅         |
| Instance | ASG         | Terminate & replace unhealthy EC2         | ✅         |
| Storage  | EFS         | Persist data across replacements          | ✅         |
| AZ       | ALB + ASG   | Shift traffic to healthy AZ               | ✅         |
| Database | RDS         | Multi-AZ standby (optional toggle)        | ⚙️         |

This design satisfies the **“fail-over automation”** requirement from the DIGITALL Task 2 specification.
