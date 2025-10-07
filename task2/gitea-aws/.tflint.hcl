# =========================
# TFLint configuration
# =========================

plugin "aws" {
  enabled = true
  version = "0.33.0" # or latest stable
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# Optional: if you use modules, let TFLint scan inside them
config {
  module = true
  force = false
}

# Common AWS rules
rule "aws_instance_invalid_type" {
  enabled = true
}

rule "aws_instance_previous_type" {
  enabled = true
}

rule "aws_security_group_invalid_name" {
  enabled = true
}

rule "aws_s3_bucket_versioning" {
  enabled = false  # disable if no S3 buckets yet
}

rule "aws_s3_bucket_logging" {
  enabled = false
}

rule "aws_db_instance_backup_retention_period" {
  enabled = true
}

rule "aws_db_instance_multi_az" {
  enabled = true
}

rule "aws_elb_deprecated" {
  enabled = true
}

rule "aws_lb_deletion_protection" {
  enabled = false  # optional for demo
}
