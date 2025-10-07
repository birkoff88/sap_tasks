# =========================
# path: task2/gitea-aws/variables.tf
# =========================
variable "project_name" {
  type        = string
  description = "Project identifier used for naming."
  validation {
    condition     = length(var.project_name) > 0
    error_message = "project_name cannot be empty."
  }
}

variable "env" {
  type        = string
  description = "Environment slug (e.g., dev, prod)."
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,12}$", var.env))
    error_message = "env should be short, lowercase, alnum/hyphen."
  }
}

variable "aws_region" {
  type        = string
  description = "AWS region."
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-\\d$", var.aws_region))
    error_message = "aws_region looks invalid."
  }
}

variable "extra_tags" {
  type        = map(string)
  description = "Extra tags merged into all resources."
  default     = {}
}

variable "app_port" {
  type        = number
  description = "Container/app port exposed via ALB."
  default     = 3000
  validation {
    condition     = var.app_port > 0 && var.app_port < 65536
    error_message = "app_port must be 1..65535."
  }
}

variable "db_port" {
  type        = number
  description = "RDS Postgres port."
  default     = 5432
  validation {
    condition     = var.db_port > 0 && var.db_port < 65536
    error_message = "db_port must be 1..65535."
  }
}

variable "db_username" {
  type        = string
  description = "RDS master username."
  default     = "gitea"
}

variable "db_name" {
  type        = string
  description = "RDS initial database name."
  default     = "gitea"
}

variable "engine_version" {
  type        = string
  description = "Postgres engine version."
  default     = "16.3"
}

variable "instance_class" {
  type        = string
  description = "RDS instance class."
  # Use a small instance class that's usually allowed on Free Tier / low-cost accounts.
  # Change this if you want a larger instance for production.
  default = "db.t4g.micro"
}

variable "allocated_storage" {
  type        = number
  description = "Initial storage (GB)."
  default     = 20
}

variable "max_allocated_storage" {
  type        = number
  description = "Max autoscaling storage (GB)."
  default     = 20
}

variable "backup_window" {
  type        = string
  description = "RDS backup window (UTC)."
  default     = "02:00-03:00"
}

variable "maintenance_window" {
  type        = string
  description = "RDS maintenance window (UTC, ddd:hh24:mi-ddd:hh24:mi)."
  default     = "Sun:03:00-Sun:04:00"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type for app nodes."
  default     = "t3.small"
}

variable "key_name" {
  type        = string
  description = "Optional EC2 key pair for SSH."
  default     = ""
}

variable "app_mount_dir" {
  type        = string
  description = "Where EFS will be mounted on EC2."
  default     = "/srv/gitea"
}

variable "asg_max" {
  type        = number
  description = "ASG max size."
  default     = 2
}

variable "asg_min" {
  type        = number
  description = "ASG min size."
  default     = 1
}

variable "asg_desired" {
  type        = number
  description = "ASG desired capacity."
  default     = 1
}

variable "gitea_version" {
  type        = string
  description = "Gitea release to install."
  default     = "1.22.0"
}