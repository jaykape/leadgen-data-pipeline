# public subnet

resource "aws_subnet" "bastion" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.32/28"
  map_public_ip_on_launch = true


  tags = {
    Name = "subnet2"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.bastion.id
  route_table_id = aws_route_table.public_rt.id
}

# EC2 for bastion and Airflow

resource "aws_security_group" "ec2" {
  name        = "lambda_and_rds"
  description = "Security group for RDS"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "leadgen_ec2"
  }
}

resource "aws_vpc_security_group_ingress_rule" "public_to_ec2" {
  security_group_id = aws_security_group.ec2.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_instance" "snap" {
  ami                    = "ami-0779c82fbb81e731c"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.bastion.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  key_name               = var.keypair
  iam_instance_profile   = aws_iam_instance_profile.ec2_airflow_profile.name
}

resource "aws_iam_role" "ec2_airflow_role" {
  name = "ec2-airflow-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "ec2_airflow_policy" {
  name = "ec2-airflow-policy"
  role = aws_iam_role.ec2_airflow_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBSnapshots",
          "rds:StartExportTask"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.rds_snapshots.arn,
          "${aws_s3_bucket.rds_snapshots.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.s3_export_key.arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_airflow_profile" {
  name = "ec2-airflow-instance-profile"
  role = aws_iam_role.ec2_airflow_role.name
}

######################################################

# S3

resource "aws_s3_bucket" "rds_snapshots" {
  bucket = "leadgen-rds-snapshots-bucket"

  tags = {
    Purpose = "RDS Snapshot Exports"
  }
}

resource "aws_kms_key" "s3_export_key" {
  description             = "KMS key for RDS snapshot exports"
  deletion_window_in_days = 7
}

######################################################

# RDS to S3 role

resource "aws_iam_role" "rds_s3_export_role" {
  name = "rds-s3-export-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "export.rds.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "rds_s3_export_policy" {
  name = "rds-s3-export-policy"
  role = aws_iam_role.rds_s3_export_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.rds_snapshots.arn,
          "${aws_s3_bucket.rds_snapshots.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.s3_export_key.arn
      }
    ]
  })
}

######################################################

# Outputs

output "airflow_instance_profile" {
  value = aws_iam_instance_profile.ec2_airflow_profile.name
}

output "rds_s3_export_role_arn" {
  value = aws_iam_role.rds_s3_export_role.arn
}

output "s3_bucket_name" {
  value = aws_s3_bucket.rds_snapshots.bucket
}

output "kms_key_arn" {
  value = aws_kms_key.s3_export_key.arn
}
