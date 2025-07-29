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

# CloudFront/WAF用のus-east-1プロバイダーを追加
provider "aws" {
  alias   = "us-east-1"
  region  = "us-east-1"
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
  enable_dns_support   = true # DNS解決を有効化
  enable_dns_hostnames = true # DNSホスト名を有効化

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
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# IAMロールを作る
resource "aws_iam_role" "role-metamon" {
  name               = "role_metamon"
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
    Name      = "ssm-endpoint"
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
    Name      = "ssmmessages-endpoint"
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
    Name      = "ec2messages-endpoint"
    createdBy = "karibeklo"
  }
}

### Lambda の SG を作成（RDSより前に定義）
resource "aws_security_group" "sg_lambda_metamon" {
  name   = "security-group-lambda-metamon"
  vpc_id = aws_vpc.metamon_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "security-group-lambda-metamon"
    createdBy = "karibeklo"
  }
}

# RDSのセキュリティグループ
resource "aws_security_group" "rds_SG_metamon" {
  name        = "securityGroup-rds-metamon"
  description = "Security group for RDS instances"
  vpc_id      = aws_vpc.metamon_vpc.id

  ingress {
    from_port       = 3306 # MySQLのポート番号
    to_port         = 3306
    protocol        = "TCP"
    security_groups = [aws_security_group.ec2_metamon.id] # EC2のセキュリティグループからのアクセスを許可
  }

  # Lambdaからのアクセスも許可
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "TCP"
    security_groups = [aws_security_group.sg_lambda_metamon.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "security-group-rds-metamon"
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
  db_name                 = "metamondb"
  username                = "admin"
  password                = "MetamonMetamon" # 本番環境では環境変数やシークレットマネージャーを使用してください
  db_subnet_group_name    = aws_db_subnet_group.metamon_db_subnet_group.name
  vpc_security_group_ids  = [aws_security_group.rds_SG_metamon.id]
  skip_final_snapshot     = true
  backup_retention_period = 0 # バックアップを保持しない設定

  tags = {
    Name      = "metamon-rds-instance"
    createdBy = "karibeklo"
  }
}

### lambda の iamrole を作る
resource "aws_iam_role" "role_lambda_metamon" {
  name = "role_lambda_metamon"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

### Lambda の iam ロールアタッチメント定義
resource "aws_iam_role_policy_attachment" "role_lambda_metamon_attachment" {
  role       = aws_iam_role.role_lambda_metamon.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda VPC実行用のポリシーも追加
resource "aws_iam_role_policy_attachment" "lambda_vpc_policy" {
  role       = aws_iam_role.role_lambda_metamon.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# lambdaのzipファイルを作成する
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "../modules/lambda/src"
  output_path = "../modules/lambda/src/lambda_function.zip"
}

### Lambda 関数定義
resource "aws_lambda_function" "lambda_metamon" {
  function_name    = "lambda-metamon"
  runtime          = "python3.10"
  role             = aws_iam_role.role_lambda_metamon.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda.output_base64sha256 # 修正：data.archive_file.lambdaを参照
  filename         = data.archive_file.lambda.output_path         # 修正：data.archive_file.lambdaを参照

  vpc_config {
    subnet_ids         = [aws_subnet.metamon_subnet_private1a.id]
    security_group_ids = [aws_security_group.sg_lambda_metamon.id]
  }

  tags = {
    Name      = "lambda-metamon-function"
    createdBy = "karibeklo"
  }
}

### REST API Gateway の定義
resource "aws_api_gateway_rest_api" "metamon_api" {
  name        = "metamon-api"
  description = "API for Metamon Lambda function"

  tags = {
    Name      = "metamon-api-gateway"
    createdBy = "karibeklo"
  }
}

# APIキーの作成
resource "aws_api_gateway_api_key" "metamon_api_key" {
  name    = "metamon-api-key"
  enabled = true

  tags = {
    Name      = "metamon-api-key"
    createdBy = "karibeklo"
  }
}

# REST API用のリソース作成
resource "aws_api_gateway_resource" "metamon_resource" {
  rest_api_id = aws_api_gateway_rest_api.metamon_api.id
  parent_id   = aws_api_gateway_rest_api.metamon_api.root_resource_id
  path_part   = "metamon"
}

# REST API用のメソッド作成
resource "aws_api_gateway_method" "metamon_method" {
  rest_api_id      = aws_api_gateway_rest_api.metamon_api.id
  resource_id      = aws_api_gateway_resource.metamon_resource.id
  http_method      = "GET"
  authorization    = "NONE"
  api_key_required = true # APIキー認証を有効化
}

# REST API用の統合
resource "aws_api_gateway_integration" "metamon_integration" {
  rest_api_id = aws_api_gateway_rest_api.metamon_api.id
  resource_id = aws_api_gateway_resource.metamon_resource.id
  http_method = aws_api_gateway_method.metamon_method.http_method

  integration_http_method = "POST" # Lambda関数を呼び出すためのHTTPメソッド
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.lambda_metamon.invoke_arn
}

# REST API用のデプロイメント
resource "aws_api_gateway_deployment" "metamon_deployment" {
  rest_api_id = aws_api_gateway_rest_api.metamon_api.id

  depends_on = [
    aws_api_gateway_method.metamon_method,
    aws_api_gateway_integration.metamon_integration,
  ]

  # デプロイメントを強制的に再作成するためのトリガー
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.metamon_resource.id,
      aws_api_gateway_method.metamon_method.id,
      aws_api_gateway_integration.metamon_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# REST API用のステージを作成
resource "aws_api_gateway_stage" "metamon_stage" {
  rest_api_id   = aws_api_gateway_rest_api.metamon_api.id
  deployment_id = aws_api_gateway_deployment.metamon_deployment.id
  stage_name    = "prod"

  tags = {
    Name      = "metamon-api-stage"
    createdBy = "karibeklo"
  }
}

# 使用量プランの作成
resource "aws_api_gateway_usage_plan" "metamon_usage_plan" {
  name        = "metamon-usage-plan"
  description = "Usage plan for Metamon API"

  api_stages {
    api_id = aws_api_gateway_rest_api.metamon_api.id
    stage  = aws_api_gateway_stage.metamon_stage.stage_name
  }

  throttle_settings {
    rate_limit  = 100
    burst_limit = 200
  }

  quota_settings {
    limit  = 10000
    period = "MONTH"
  }

  tags = {
    Name      = "metamon-usage-plan"
    createdBy = "karibeklo"
  }
}

# 使用量プランとAPIキーの関連付け
resource "aws_api_gateway_usage_plan_key" "metamon_usage_plan_key" {
  key_id        = aws_api_gateway_api_key.metamon_api_key.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.metamon_usage_plan.id
}

# Lambda関数の実行権限をAPI Gatewayに付与
resource "aws_lambda_permission" "allow_api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_metamon.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.metamon_api.execution_arn}/*/*"
}

# ==== WAF設定（IP制限のみ） ====

# 許可するIPアドレスのIPセット（us-east-1で作成）
resource "aws_wafv2_ip_set" "metamon_allowed_ips" {
  provider = aws.us-east-1  # us-east-1プロバイダーを指定
  
  name  = "metamon-allowed-ips"
  scope = "CLOUDFRONT"

  ip_address_version = "IPV4"
  
  addresses = [
    "133.127.0.0/16", # NHKイントラ
    "210.138.88.12/32" # デジタルセンターVPN  
  ]

  tags = {
    Name      = "metamon-allowed-ips"
    createdBy = "karibeklo"
  }
}

# WAF Web ACL の作成（us-east-1で作成）
resource "aws_wafv2_web_acl" "metamon_waf" {
  provider = aws.us-east-1  # us-east-1プロバイダーを指定
  
  name  = "metamon-waf-acl"
  scope = "CLOUDFRONT"

  default_action {
    block {}
  }

  rule {
    name     = "AllowSpecificIPs"
    priority = 1

    action {
      allow {}
    }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.metamon_allowed_ips.arn
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AllowSpecificIPs"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "metamonWAF"
    sampled_requests_enabled   = true
  }

  tags = {
    Name      = "metamon-waf"
    createdBy = "karibeklo"
  }
}

# CloudFront Distribution（ap-northeast-1で作成可能）
resource "aws_cloudfront_distribution" "metamon_distribution" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "CloudFront distribution for Metamon API"

  origin {
    domain_name = replace(aws_api_gateway_stage.metamon_stage.invoke_url, "/^https?://([^/]*).*/", "$1")
    origin_id   = "metamon-api-gateway"
    origin_path = "/prod"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "X-API-Key"
      value = aws_api_gateway_api_key.metamon_api_key.value
    }
  }

  default_cache_behavior {
    target_origin_id       = "metamon-api-gateway"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods  = ["GET", "HEAD"]

    forwarded_values {
      query_string = true
      headers      = ["Authorization"]

      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  # WAFとの関連付け
  web_acl_id = aws_wafv2_web_acl.metamon_waf.arn

  tags = {
    Name      = "metamon-cloudfront"
    createdBy = "karibeklo"
  }
}
