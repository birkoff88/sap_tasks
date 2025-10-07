# Makefile — quick wrappers for Terraform
SHELL := /usr/bin/env bash

.PHONY: init plan apply outputs open destroy fmt validate refresh

init:
	terraform init

fmt:
	terraform fmt -recursive

validate:
	terraform validate

plan: fmt validate
	terraform plan -out=tfplan

apply:
	terraform apply -auto-approve tfplan || terraform apply -auto-approve

outputs:
	@echo "ALB  : http://$$(terraform output -raw alb_dns_name)"
	@echo "RDS  : $$(terraform output -raw rds_endpoint)"
	@echo "SECRET: $$(terraform output -raw db_secret_arn)"

open:
	@if command -v open >/dev/null; then \
		open "http://$$(terraform output -raw alb_dns_name)"; \
	elif command -v xdg-open >/dev/null; then \
		xdg-open "http://$$(terraform output -raw alb_dns_name)"; \
	else \
		echo "Open this in your browser:"; \
		terraform output -raw alb_dns_name; \
	fi

destroy:
	terraform destroy -auto-approve

# Roll ASG when LT changes (optional force refresh)
refresh:
	aws autoscaling start-instance-refresh --auto-scaling-group-name "$$(terraform state show aws_autoscaling_group.app | awk -F'= ' '/name +=/{print $$2}' | xargs)" --preferences MinHealthyPercentage=90,InstanceWarmup=60 || true
