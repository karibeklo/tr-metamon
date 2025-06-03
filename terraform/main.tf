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
    Name = "metamon-vpc"
    createdBy = "karibeklo"
  }
}

# サブネットを作る
resource "aws_subnet" "metamon_subnet_private1a" {
  vpc_id            = aws_vpc.metamon_vpc.id
  cidr_block        = "192.168.2.0/24"
  availability_zone = "ap-northeast-1a"
  tags = {
    Name = "metamon-subnet-private1a"
    createdBy = "karibeklo"
  }
}

resource "aws_subnet" "metamon_subnet_private1c" {
  vpc_id            = aws_vpc.metamon_vpc.id
  cidr_block        = "192.168.3.0/24"
  availability_zone = "ap-northeast-1c"
  tags = {
    Name = "metamon-subnet-private1c"
    createdBy = "karibeklo"
  }
}

# IAMロールを作る
resource "aws_iam_role" "role_metamon" {
  name = "role-metamon"
    assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    createdBy = "karibeklo"
  }
}

# SSM用のIAMインスタンスプロファイル
resource "aws_iam_instance_profile" "role_metamon" {
  name = "ssm-instance-profile"
  role = aws_iam_role.ssm_role.name
}

# SSM接続ポリシーをアタッチ
resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}