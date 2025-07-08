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

# API Gatewayのアウトプット
output "api_gateway_url" {
  description = "The URL of the API Gateway"
  value       = "${aws_api_gatewayv2_api.metamon_api.api_endpoint}/metamon"
}