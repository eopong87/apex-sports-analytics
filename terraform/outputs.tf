output "primary_bucket_name" {
  description = "Primary S3 bucket name"
  value       = aws_s3_bucket.primary.id
}

output "secondary_bucket_name" {
  description = "Secondary S3 bucket name"
  value       = aws_s3_bucket.secondary.id
}

output "primary_website_url" {
  description = "Primary S3 static website URL"
  value       = "http://${aws_s3_bucket_website_configuration.primary.website_endpoint}"
}

output "secondary_website_url" {
  description = "Secondary S3 static website URL"
  value       = "http://${aws_s3_bucket_website_configuration.secondary.website_endpoint}"
}

output "sports_api_url" {
  description = "API Gateway invoke URL"
  value       = var.enable_backend ? aws_apigatewayv2_stage.default[0].invoke_url : "Backend disabled"
}

output "sports_api_routes" {
  description = "Available API routes"
  value = var.enable_backend ? [
    "GET /nba/scores",
    "GET /nfl/scores",
    "GET /mlb/scores",
    "GET /odds/props",
    "GET /ai/insights",
  ] : []
}

output "api_secret_name" {
  description = "Secrets Manager secret name for API keys"
  value       = var.enable_backend ? aws_secretsmanager_secret.api_keys[0].name : "Backend disabled"
}

output "eventbridge_schedules_state" {
  description = "EventBridge schedule state"
  value       = var.enable_eventbridge_schedules ? "ENABLED" : "DISABLED"
}

output "kinesis_stream_name" {
  description = "Kinesis stream name"
  value       = var.enable_kinesis_stream ? aws_kinesis_stream.live_stream[0].name : "Kinesis stream disabled"
}
