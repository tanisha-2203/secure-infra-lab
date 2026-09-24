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

# Lab only: scanned by Checkov, never deployed. NEVER run terraform apply.

# --- Network ---
resource "aws_vpc" "lab" {
  #checkov:skip=CKV2_AWS_11:Lab only, never deployed. Production needs flow logs to CloudWatch or S3.
  cidr_block = "10.0.0.0/16"
}

resource "aws_default_security_group" "lab" {
  vpc_id = aws_vpc.lab.id
  # No ingress or egress rules: the default security group denies all traffic.
}

resource "aws_security_group" "web" {
  #checkov:skip=CKV2_AWS_5:Lab has no server to attach this to.
  name        = "lab-web-sg"
  description = "Web server"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description = "SSH from inside the VPC only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.lab.cidr_block]
  }
}

# --- Storage ---
resource "aws_s3_bucket" "payments_data" {
  #checkov:skip=CKV_AWS_145:Lab only. Production would use a customer-managed KMS key.
  #checkov:skip=CKV_AWS_18:Lab only. Production needs access logging to a separate log bucket.
  #checkov:skip=CKV_AWS_144:Lab only. Cross-region replication is a resilience choice, not needed here.
  #checkov:skip=CKV2_AWS_61:Lab only. Lifecycle rules depend on data retention requirements.
  #checkov:skip=CKV2_AWS_62:Lab only. No consumer exists for bucket event notifications.
  bucket = "lab-payments-data-example-12345"
}

resource "aws_s3_bucket_public_access_block" "payments_data" {
  bucket                  = aws_s3_bucket.payments_data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "payments_data" {
  bucket = aws_s3_bucket.payments_data.id
  versioning_configuration {
    status = "Enabled"
  }
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

resource "aws_iam_role_policy" "app_s3_access" {
  name = "lab-app-s3-access"
  role = aws_iam_role.app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.payments_data.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.payments_data.arn
      }
    ]
  })
}
