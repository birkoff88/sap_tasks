# Architecture Overview – Gitea AWS Stack

```
[User]
   ↓
 [AWS ALB] —(HTTP/80)→ [AutoScaling Group of EC2 Instances]
                                │
                                ├─ Mount EFS (/data/gitea)
                                └─ Connect to RDS (PostgreSQL)
```

**Data Flow**
1. ALB distributes inbound HTTP traffic across ASG instances.  
2. Each instance mounts the EFS volume (/data/gitea).  
3. Application connects to RDS (PostgreSQL).  
4. CloudWatch collects metrics and logs.  
5. Terraform manages full stack lifecycle.

**High Availability**
- Multi-AZ ASG with min 2 instances.  
- ALB health checks ensure replacement.  
- EFS and RDS support multi-AZ.

**Security**
- Least-privilege Security Groups  
- Encrypted storage and network  
- IMDSv2 required on EC2  
