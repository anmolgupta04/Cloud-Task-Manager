variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (development | staging | production)"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "project" {
  description = "Project name prefix for all resources"
  type        = string
  default     = "task-manager"
}

variable "db_instance_class" {
  description = "RDS PostgreSQL instance type"
  type        = string
  default     = "db.t3.medium"
}

variable "db_password" {
  description = "RDS master password — supply via TF_VAR_db_password or tfvars"
  type        = string
  sensitive   = true
}

variable "eks_node_instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "eks_desired_nodes" {
  description = "Desired number of EKS worker nodes"
  type        = number
  default     = 3
}

variable "eks_min_nodes" {
  description = "Minimum EKS nodes (auto-scaling)"
  type        = number
  default     = 2
}

variable "eks_max_nodes" {
  description = "Maximum EKS nodes (auto-scaling)"
  type        = number
  default     = 10
}

variable "allow_render_inbound" {
  description = "If true, allow inbound access from Render's outbound IP ranges to RDS/Redis (use with caution)."
  type        = bool
  default     = false
}

variable "render_outbound_cidrs" {
  description = "CIDR ranges used by Render (shared)."
  type        = list(string)
  default     = ["74.220.52.0/24", "74.220.60.0/24"]
}
