terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
  }

  # Remote state in S3
  backend "s3" {
    bucket         = "task-manager-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "cloud-task-manager"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}


# ── VPC ─────────────────────────────────────────────────────
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.3"

  name = "${var.project}-${var.environment}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = false  # HA: one per AZ
  enable_dns_hostnames   = true
  enable_dns_support     = true

  # Required tags for EKS
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"                         = "1"
    "kubernetes.io/cluster/${var.project}-${var.environment}" = "shared"
  }
  public_subnet_tags = {
    "kubernetes.io/role/elb"                                  = "1"
    "kubernetes.io/cluster/${var.project}-${var.environment}" = "shared"
  }
}


# ── EKS Cluster ─────────────────────────────────────────────
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.8.4"

  cluster_name    = "${var.project}-${var.environment}"
  cluster_version = "1.29"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true

  # Managed node groups
  eks_managed_node_groups = {
    app_nodes = {
      instance_types = ["t3.medium"]
      ami_type       = "AL2_x86_64"
      disk_size      = 50

      min_size     = 2
      max_size     = 10
      desired_size = 3

      labels = {
        role = "app"
      }
    }
  }

  # Add-ons
  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni    = { most_recent = true }
    aws-ebs-csi-driver = { most_recent = true }
  }
}


# ── RDS PostgreSQL ───────────────────────────────────────────
resource "aws_db_subnet_group" "postgres" {
  name       = "${var.project}-${var.environment}-db"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_security_group" "postgres" {
  name        = "${var.project}-postgres-sg"
  description = "Allow PostgreSQL from EKS nodes"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  dynamic "ingress" {
    for_each = var.allow_render_inbound ? var.render_outbound_cidrs : []
    content {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
      description = "Allow Render outbound IP range"
    }
  }
}

resource "aws_db_instance" "postgres" {
  identifier        = "${var.project}-${var.environment}"
  engine            = "postgres"
  engine_version    = "15.6"
  instance_class    = var.db_instance_class
  allocated_storage = 20
  storage_encrypted = true

  db_name  = "taskdb"
  username = "taskadmin"
  password = var.db_password   # From tfvars / Secrets Manager

  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.postgres.id]

  multi_az               = var.environment == "production" ? true : false
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"
  deletion_protection     = var.environment == "production" ? true : false

  skip_final_snapshot     = var.environment != "production"
  final_snapshot_identifier = "${var.project}-final-snapshot"
}


# ── ElastiCache Redis ────────────────────────────────────────
resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.project}-${var.environment}-redis"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_security_group" "redis" {
  name        = "${var.project}-redis-sg"
  description = "Allow Redis from EKS nodes"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  dynamic "ingress" {
    for_each = var.allow_render_inbound ? var.render_outbound_cidrs : []
    content {
      from_port   = 6379
      to_port     = 6379
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
      description = "Allow Render outbound IP range"
    }
  }
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "${var.project}-${var.environment}"
  description          = "Redis cache for Task Manager"

  node_type               = "cache.t3.micro"
  num_cache_clusters      = 2    # primary + 1 replica
  port                    = 6379
  parameter_group_name    = "default.redis7"
  engine_version          = "7.1"
  automatic_failover_enabled = true

  subnet_group_name       = aws_elasticache_subnet_group.redis.name
  security_group_ids      = [aws_security_group.redis.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
}


# ── ECR Repository ───────────────────────────────────────────
resource "aws_ecr_repository" "api" {
  name                 = "${var.project}-api"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
