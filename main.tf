terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1"
}

# INSECURE ON PURPOSE - for scanner practice only. NEVER run terraform apply.

# --- Network ---
resource "aws_vpc" "lab" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_security_group" "web" {
  name        = "lab-web-sg"
  description = "Web server"
  vpc_id      = aws_vpc.lab.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- Storage ---
resource "aws_s3_bucket" "payments_data" {
  bucket = "lab-payments-data-example-12345"
}

resource "aws_s3_bucket_public_access_block" "payments_data" {
  bucket                  = aws_s3_bucket.payments_data.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# --- Identity ---
resource "aws_iam_role" "app" {
  name = "lab-app-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "app_admin" {
  name = "lab-app-admin-everything"
  role = aws_iam_role.app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "*"
      Resource = "*"
    }]
  })
}
