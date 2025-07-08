# おまじない
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

# プロバイダーの設定
provider "aws" {
  region  = "ap-northeast-1"
  profile = "mic-plus"
}

# 最新のAmazon Linux 2 AMIを取得
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# VPCを作る
resource "aws_vpc" "metamon_vpc" {
  cidr_block           = "192.168.0.0/16"
  enable_dns_support   = true  # DNS解決を有効化
  enable_dns_hostnames = true  # DNSホスト名を有効化
  
  tags = {
    Name      = "metamon-vpc"
    createdBy = "karibeklo"
  }
}

# サブネットを作る
resource "aws_subnet" "metamon_subnet_private1a" {
  vpc_id            = aws_vpc.metamon_vpc.id
  cidr_block        = "192.168.2.0/24"
  availability_zone = "ap-northeast-1a"
  tags = {
    Name      = "metamon-subnet-private1a"
    createdBy = "karibeklo"
  }
}

resource "aws_subnet" "metamon_subnet_private1c" {
  vpc_id            = aws_vpc.metamon_vpc.id
  cidr_block        = "192.168.3.0/24"
  availability_zone = "ap-northeast-1c"
  tags = {
    Name      = "metamon-subnet-private1c"
    createdBy = "karibeklo"
  }
}

# DBサブネットグループを作る（RDS用）
resource "aws_db_subnet_group" "metamon_db_subnet_group" {
  name       = "metamon-db-subnet-group"
  subnet_ids = [aws_subnet.metamon_subnet_private1a.id, aws_subnet.metamon_subnet_private1c.id]

  tags = {
    Name      = "metamon-db-subnet-group"
    createdBy = "karibeklo"
  }
}

# セキュリティグループ - EC2用（SSMアクセス用）
resource "aws_security_group" "ec2_metamon" {
  name        = "securityGroup-ec2-metamon-SSM"
  description = "Security group for EC2 instances with SSM access"
  vpc_id      = aws_vpc.metamon_vpc.id
  
  # アウトバウンドトラフィック許可 - VPCエンドポイントへの接続用
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2-metamon-sg"
  }
}

# VPCエンドポイント用のセキュリティグループ
resource "aws_security_group" "vpc_endpoint_sg" {
  name        = "vpc-endpoint-sg"
  description = "Security group for VPC Endpoints"
  vpc_id      = aws_vpc.metamon_vpc.id
  
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.metamon_subnet_private1a.cidr_block, aws_subnet.metamon_subnet_private1c.cidr_block]
  }

  tags = {
    Name = "vpc-endpoint-sg"
  }
}

# IAM ポリシー定義
data "aws_iam_policy_document" "instance-assume-role-policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# IAMロールを作る
resource "aws_iam_role" "role-metamon" {
  name = "role_metamon"
  assume_role_policy = data.aws_iam_policy_document.instance-assume-role-policy.json
  tags = {
    createdBy = "karibeklo"
  }
}

# SSM接続ポリシーをアタッチ
resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.role-metamon.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# プロファイル定義
resource "aws_iam_instance_profile" "metamon_instance_profile" {
  name = "metamon_instance_profile"
  role = aws_iam_role.role-metamon.name
}

# EC2インスタンスを作る
resource "aws_instance" "metamon_ec2" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.metamon_subnet_private1a.id
  iam_instance_profile   = aws_iam_instance_profile.metamon_instance_profile.name
  vpc_security_group_ids = [aws_security_group.ec2_metamon.id]

  tags = {
    Name      = "metamon-ec2-instance"
    createdBy = "karibeklo"
  }
}

# ==== VPCエンドポイント設定 ====

# SSM用のVPCエンドポイント
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.metamon_vpc.id
  service_name        = "com.amazonaws.ap-northeast-1.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.metamon_subnet_private1a.id]
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true
  
  tags = {
    Name = "ssm-endpoint"
    createdBy = "karibeklo"
  }
}

# SSM Messages用のVPCエンドポイント
resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.metamon_vpc.id
  service_name        = "com.amazonaws.ap-northeast-1.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.metamon_subnet_private1a.id]
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true
  tags = {
    Name = "ssmmessages-endpoint"
    createdBy = "karibeklo"
  }
}

# EC2 Messages用のVPCエンドポイント
resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.metamon_vpc.id
  service_name        = "com.amazonaws.ap-northeast-1.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.metamon_subnet_private1a.id]
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true
  
  tags = {
    Name = "ec2messages-endpoint"
    createdBy = "karibeklo"
  }
}

# RDSのセキュリティグループ
resource "aws_security_group" "rds_SG_metamon" {
  name        = "securityGroup-rds-metamon"
  description = "Security group for RDS instances"
  vpc_id      = aws_vpc.metamon_vpc.id
  
  ingress {
    from_port = 5432
    to_port = 5432
    protocol = "TCP"
    security_groups = [aws_security_group.ec2_metamon.id]  # EC2のセキュリティグループからのアクセスを許可
  }

  egress {
  from_port = 0
  to_port = 0
  protocol = "-1"  # Allow all protocols.
  cidr_blocks = ["0.0.0.0/0"]
}

  tags = {
    Name = "security-group-rds-metamon"
    createdBy = "karibeklo"
  }
}

# RDSインスタンスを作る
resource "aws_db_instance" "rds_metamon" {
  identifier              = "rds-metamon-mysql"
  engine                  = "mysql"
  engine_version          = "8.0"
  allocated_storage       = 20
  instance_class          = "db.t3.micro"
  storage_type            = "gp2"
  db_name                 = "metamondb"
  username                = "admin"
  password                = "MetamonMetamon"  # 本番環境では環境変数やシークレットマネージャーを使用してください
  db_subnet_group_name    = aws_db_subnet_group.metamon_db_subnet_group.name
  vpc_security_group_ids  = [aws_security_group.rds_SG_metamon.id]
  skip_final_snapshot     = true
  backup_retention_period = 0 # バックアップを保持しない設定

  tags = {
    Name      = "metamon-rds-instance"
    createdBy = "karibeklo"
  }
}

# lambdaのzipファイルを作成する
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "./modules/lambda/src"
  output_path = "./modules/lambda/src/lambda_function_payload.zip"
}

# IAMロールを作成する
data "aws_iam_policy_document" "lambda_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# lambda関数を作成する
resource "aws_lambda_function" "main" {
  filename         = "./modules/lambda/src/lambda_function_payload.zip"
  function_name    = "lambda_function"
  description      = "lambda_function"
  role             = var.iam_role_lambda
  architectures    = ["x86_64"]
  handler          = "index.lambda_handler"
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 30
  runtime          = "python3.9"

  vpc_config {
    subnet_ids         = [var.subnet_public_subnet_1a_id]
    security_group_ids = [var.sg_lambda_id]
  }

  environment {
    variables = {
      db_host = var.db_address
      db_user = var.db_username
      db_pass = var.db_password
      db_name = var.db_name
    }
  }
  tags = {
    Name = "${var.app_name}-lamdba"
  }
}
