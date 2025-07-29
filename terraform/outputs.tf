output "ec2_id" {
  description = "ec2 の id"
  value = aws_instance.metamon_ec2.id
}

# アウトプット（RDS接続情報）
output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.rds_metamon.endpoint
}

output "rds_port" {
  description = "RDS instance port"
  value       = aws_db_instance.rds_metamon.port
}

# APIキーの値を出力
output "api_key_value" {
  value     = aws_api_gateway_api_key.metamon_api_key.value
  sensitive = true
  description = "The API key value for accessing the Metamon API"
}

# API エンドポイントURLを出力
output "api_endpoint" {
  value = "https://${aws_api_gateway_rest_api.metamon_api.id}.execute-api.ap-northeast-1.amazonaws.com/prod/metamon"
  description = "The API endpoint URL"
}

# CloudFront Distribution ID
output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.metamon_distribution.id
  description = "CloudFront Distribution ID"
}