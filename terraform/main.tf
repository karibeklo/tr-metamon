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

# VPCを作る
resource "aws_vpc" "metamon_vpc" {
  cidr_block = "192.168.0.0/16"
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

# セキュリティグループ - EC2用（SSMアクセス用）
resource "aws_security_group" "ec2_metamon" {
  name        = "securityGroup-ec2-metamon-SSM"
  description = "Security group for EC2 instances with SSM access"
  vpc_id      = aws_vpc.metamon_vpc.id
  
  # SSMを使用する場合、インバウンドルールは基本的に必要ありません
  # 必要なアプリケーションポートがある場合のみ追加
  
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
  ami           = "ami-0c55b159cbfafe1f0" # Amazon Linux 2のAMI ID（最新のものを使用）
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.metamon_subnet_private1a.id
  iam_instance_profile = aws_iam_instance_profile.metamon_instance_profile.name
  security_groups = [aws_security_group.ec2_metamon.name]

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
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true
  
  tags = {
    Name = "ec2messages-endpoint"
    createdBy = "karibeklo"
  }
}

