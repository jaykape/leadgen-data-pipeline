terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.11.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1"
}

######################################################################

# VPC, subnets, security groups

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/24"

  tags = {
    Name = "leadgen"
  }
}

resource "aws_subnet" "main" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.0.0/28"
  availability_zone = "ap-southeast-1a"

  tags = {
    Name = "subnet1"
  }
}

resource "aws_subnet" "main2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.0.16/28"
  availability_zone = "ap-southeast-1b"

  tags = {
    Name = "subnet3"
  }
}


resource "aws_security_group" "lambda" {
  name        = "lambda"
  description = "Security group for Lambda"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "leadgen_lambda"
  }
}

resource "aws_security_group" "rds" {
  name        = "rds"
  description = "Security group for RDS"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "leadgen_rds"
  }
}

resource "aws_vpc_security_group_ingress_rule" "lambda_to_rds" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.lambda.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_vpc_security_group_ingress_rule" "ec2_to_rds" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.ec2.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_vpc_security_group_egress_rule" "ec2_to_any" {
  security_group_id            = aws_security_group.lambda.id
  referenced_security_group_id = aws_security_group.rds.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}


######################################################################

# RDS 

resource "aws_db_instance" "postgres" {
  allocated_storage      = 10
  db_name                = "mydb"
  engine                 = "postgres"
  instance_class         = "db.t4g.micro"
  username               = var.db_username
  password               = var.db_password
  skip_final_snapshot    = true
  db_subnet_group_name   = aws_db_subnet_group.db_subnet.id
  vpc_security_group_ids = [aws_security_group.rds.id]
}

resource "aws_db_subnet_group" "db_subnet" {
  name        = "db-subnet-group"
  subnet_ids  = [aws_subnet.main.id, aws_subnet.main2.id]
  description = "Subnet group for RDS"
}

######################################################################

# Lambda

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda" {
  name               = "lambda_execution_role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy" "lambda_vpc_policy" {
  name = "lambda_vpc_policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:AttachNetworkInterface"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logging" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "archive_file" "code" {
  type        = "zip"
  source_file = "../lambda/main.py"
  output_path = "../lambda/function.zip"
}

resource "aws_lambda_layer_version" "my_layer" {
  filename            = "../lambda/psycopg2.zip"
  layer_name          = "psycopg2"
  compatible_runtimes = ["python3.13"]
}


resource "aws_lambda_permission" "allow_http_api" {
  statement_id  = "AllowExecutionFromHttpApi"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.leadgen.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.leadgen.execution_arn}/*/*"
}

resource "aws_lambda_function" "leadgen" {
  filename         = data.archive_file.code.output_path
  function_name    = "leadgen"
  role             = aws_iam_role.lambda.arn
  handler          = "main.handler"
  source_code_hash = data.archive_file.code.output_base64sha256
  runtime          = "python3.13"
  layers           = [aws_lambda_layer_version.my_layer.arn]
  environment {
    variables = {
      DB_HOST = aws_db_instance.postgres.address
      DB_USER = var.db_username
      DB_PASS = var.db_password
      DB_NAME = "mydb"
    }
  }

  vpc_config {
    subnet_ids         = [aws_subnet.main.id]
    security_group_ids = [aws_security_group.lambda.id]
  }
}

######################################################################

# API Gateway

resource "aws_apigatewayv2_api" "leadgen" {
  name          = "lead-http-api"
  protocol_type = "HTTP"
}


resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                 = aws_apigatewayv2_api.leadgen.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.leadgen.arn
  payload_format_version = "2.0"
}


resource "aws_apigatewayv2_route" "leadgen" {
  api_id    = aws_apigatewayv2_api.leadgen.id
  route_key = "POST /leadgen"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}


resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.leadgen.id
  name        = "prod"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw_logs.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      userAgent      = "$context.identity.userAgent"
    })
  }
}

resource "aws_cloudwatch_log_group" "api_gw_logs" {
  name              = "/aws/apigateway/http-api"
  retention_in_days = 7
}
