locals {
  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ── Primary S3 Bucket ─────────────────────────────────────────────────────────
resource "aws_s3_bucket" "primary" {
  provider      = aws.primary
  bucket        = "${var.bucket_prefix}-primary"
  force_destroy = true
  tags          = local.tags
}

resource "aws_s3_bucket_versioning" "primary" {
  provider = aws.primary
  bucket   = aws_s3_bucket.primary.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_website_configuration" "primary" {
  provider = aws.primary
  bucket   = aws_s3_bucket.primary.id
  index_document { suffix = "index.html" }
  error_document { key    = "error.html" }
}

resource "aws_s3_bucket_public_access_block" "primary" {
  provider                = aws.primary
  bucket                  = aws_s3_bucket.primary.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "primary_public_read" {
  provider   = aws.primary
  bucket     = aws_s3_bucket.primary.id
  depends_on = [aws_s3_bucket_public_access_block.primary]
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadForWebsite"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.primary.arn}/*"
    }]
  })
}

resource "aws_s3_object" "primary_website_files" {
  provider     = aws.primary
  for_each     = fileset("${path.module}/../website", "*.html")
  bucket       = aws_s3_bucket.primary.id
  key          = each.value
  source       = "${path.module}/../website/${each.value}"
  content_type = "text/html"
  etag         = filemd5("${path.module}/../website/${each.value}")
  depends_on   = [aws_s3_bucket_policy.primary_public_read]
}

# ── Secondary S3 Bucket ───────────────────────────────────────────────────────
resource "aws_s3_bucket" "secondary" {
  provider      = aws.secondary
  bucket        = "${var.bucket_prefix}-secondary"
  force_destroy = true
  tags          = local.tags
}

resource "aws_s3_bucket_versioning" "secondary" {
  provider = aws.secondary
  bucket   = aws_s3_bucket.secondary.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_website_configuration" "secondary" {
  provider = aws.secondary
  bucket   = aws_s3_bucket.secondary.id
  index_document { suffix = "index.html" }
  error_document { key    = "error.html" }
}

resource "aws_s3_bucket_public_access_block" "secondary" {
  provider                = aws.secondary
  bucket                  = aws_s3_bucket.secondary.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "secondary_public_read" {
  provider   = aws.secondary
  bucket     = aws_s3_bucket.secondary.id
  depends_on = [aws_s3_bucket_public_access_block.secondary]
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadForWebsite"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.secondary.arn}/*"
    }]
  })
}

# ── IAM Replication Role ──────────────────────────────────────────────────────
resource "aws_iam_role" "replication" {
  provider = aws.primary
  name     = "${var.project_name}-replication-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.tags
}

resource "aws_iam_policy" "replication" {
  provider = aws.primary
  name     = "${var.project_name}-replication-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:GetReplicationConfiguration","s3:ListBucket"]
        Resource = [aws_s3_bucket.primary.arn]
      },
      {
        Effect = "Allow"
        Action = ["s3:GetObjectVersionForReplication","s3:GetObjectVersionAcl","s3:GetObjectVersionTagging"]
        Resource = ["${aws_s3_bucket.primary.arn}/*"]
      },
      {
        Effect = "Allow"
        Action = ["s3:ReplicateObject","s3:ReplicateDelete","s3:ReplicateTags"]
        Resource = ["${aws_s3_bucket.secondary.arn}/*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "replication" {
  provider   = aws.primary
  role       = aws_iam_role.replication.name
  policy_arn = aws_iam_policy.replication.arn
}

# ── S3 Replication ────────────────────────────────────────────────────────────
resource "aws_s3_bucket_replication_configuration" "primary_to_secondary" {
  provider   = aws.primary
  depends_on = [aws_s3_bucket_versioning.primary]
  bucket     = aws_s3_bucket.primary.id
  role       = aws_iam_role.replication.arn
  rule {
    id     = "replicate-to-secondary"
    status = "Enabled"
    filter {}
    destination {
      bucket        = aws_s3_bucket.secondary.arn
      storage_class = "STANDARD"
    }
    delete_marker_replication { status = "Enabled" }
  }
}

# ── Route 53 Failover (optional) ──────────────────────────────────────────────
resource "aws_route53_health_check" "primary" {
  count             = var.enable_route53_failover ? 1 : 0
  fqdn              = aws_s3_bucket_website_configuration.primary.website_endpoint
  port              = 80
  type              = "HTTP"
  resource_path     = "/index.html"
  failure_threshold = 3
  request_interval  = 30
  tags              = local.tags
}

resource "aws_route53_record" "primary_failover" {
  count           = var.enable_route53_failover ? 1 : 0
  zone_id         = var.hosted_zone_id
  name            = var.domain_name
  type            = "CNAME"
  ttl             = 60
  set_identifier  = "primary"
  records         = [aws_s3_bucket_website_configuration.primary.website_endpoint]
  failover_routing_policy { type = "PRIMARY" }
  health_check_id = aws_route53_health_check.primary[0].id
}

resource "aws_route53_record" "secondary_failover" {
  count          = var.enable_route53_failover ? 1 : 0
  zone_id        = var.hosted_zone_id
  name           = var.domain_name
  type           = "CNAME"
  ttl            = 60
  set_identifier = "secondary"
  records        = [aws_s3_bucket_website_configuration.secondary.website_endpoint]
  failover_routing_policy { type = "SECONDARY" }
}

# ── DynamoDB Tables ───────────────────────────────────────────────────────────
resource "aws_dynamodb_table" "sports" {
  provider     = aws.primary
  count        = var.enable_backend ? 5 : 0
  name         = "${var.project_name}-${["live-games","player-stats","team-stats","betting-odds","ai-insights"][count.index]}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = ["gameId","playerId","teamId","oddsId","insightId"][count.index]

  attribute {
    name = ["gameId","playerId","teamId","oddsId","insightId"][count.index]
    type = "S"
  }
  tags = local.tags
}

# ── Secrets Manager ───────────────────────────────────────────────────────────
resource "aws_secretsmanager_secret" "api_keys" {
  provider                = aws.primary
  count                   = var.enable_backend ? 1 : 0
  name                    = "${var.project_name}/api-keys"
  recovery_window_in_days = 0
  tags                    = local.tags
}

resource "aws_secretsmanager_secret_version" "api_keys" {
  provider  = aws.primary
  count     = var.enable_backend ? 1 : 0
  secret_id = aws_secretsmanager_secret.api_keys[0].id
  secret_string = jsonencode({
    sportradar_master_key = "placeholder"
    odds_api_key          = "placeholder"
    gemini_api_key        = "placeholder"
  })
}

# ── Lambda IAM Role ───────────────────────────────────────────────────────────
resource "aws_iam_role" "lambda" {
  provider = aws.primary
  count    = var.enable_backend ? 1 : 0
  name     = "${var.project_name}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  provider   = aws.primary
  count      = var.enable_backend ? 1 : 0
  role       = aws_iam_role.lambda[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb" {
  provider   = aws.primary
  count      = var.enable_backend ? 1 : 0
  role       = aws_iam_role.lambda[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_secrets" {
  provider   = aws.primary
  count      = var.enable_backend ? 1 : 0
  role       = aws_iam_role.lambda[0].name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

# ── Lambda Functions ──────────────────────────────────────────────────────────
locals {
  lambda_functions = {
    nba-fetcher  = "nba"
    nfl-fetcher  = "nfl"
    mlb-fetcher  = "mlb"
    odds-fetcher = "odds"
    ai-analysis  = "ai"
  }
}

data "archive_file" "lambda_zip" {
  for_each    = var.enable_backend ? local.lambda_functions : {}
  type        = "zip"
  output_path = "/tmp/${each.key}.zip"
  source {
    content  = <<PYEOF
import json
from datetime import datetime, timezone

def lambda_handler(event, context):
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
        "body": json.dumps({
            "service": "${each.key}",
            "message": "Endpoint deployed. Add provider logic to go live.",
            "timestamp": datetime.now(timezone.utc).isoformat()
        })
    }
PYEOF
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "sports" {
  provider         = aws.primary
  for_each         = var.enable_backend ? local.lambda_functions : {}
  function_name    = "${var.project_name}-${each.key}"
  role             = aws_iam_role.lambda[0].arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip[each.key].output_path
  source_code_hash = data.archive_file.lambda_zip[each.key].output_base64sha256
  timeout          = 30
  memory_size      = 256
  tags             = local.tags
}

# ── API Gateway ───────────────────────────────────────────────────────────────
resource "aws_apigatewayv2_api" "sports" {
  provider      = aws.primary
  count         = var.enable_backend ? 1 : 0
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET","OPTIONS"]
    allow_headers = ["*"]
  }
  tags = local.tags
}

resource "aws_apigatewayv2_stage" "default" {
  provider    = aws.primary
  count       = var.enable_backend ? 1 : 0
  api_id      = aws_apigatewayv2_api.sports[0].id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "sports" {
  provider               = aws.primary
  for_each               = var.enable_backend ? local.lambda_functions : {}
  api_id                 = aws_apigatewayv2_api.sports[0].id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.sports[each.key].invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "sports" {
  provider  = aws.primary
  for_each  = var.enable_backend ? {
    nba-fetcher  = "GET /nba/scores"
    nfl-fetcher  = "GET /nfl/scores"
    mlb-fetcher  = "GET /mlb/scores"
    odds-fetcher = "GET /odds/props"
    ai-analysis  = "GET /ai/insights"
  } : {}
  api_id    = aws_apigatewayv2_api.sports[0].id
  route_key = each.value
  target    = "integrations/${aws_apigatewayv2_integration.sports[each.key].id}"
}

resource "aws_lambda_permission" "api_gateway" {
  provider      = aws.primary
  for_each      = var.enable_backend ? local.lambda_functions : {}
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sports[each.key].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.sports[0].execution_arn}/*/*"
}

# ── EventBridge Schedules (optional) ─────────────────────────────────────────
resource "aws_cloudwatch_event_rule" "lambda_schedule" {
  provider            = aws.primary
  for_each            = var.enable_backend && var.enable_eventbridge_schedules ? local.lambda_functions : {}
  name                = "${var.project_name}-${each.key}-schedule"
  schedule_expression = "rate(5 minutes)"
  state               = var.enable_eventbridge_schedules ? "ENABLED" : "DISABLED"
  tags                = local.tags
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  provider  = aws.primary
  for_each  = var.enable_backend && var.enable_eventbridge_schedules ? local.lambda_functions : {}
  rule      = aws_cloudwatch_event_rule.lambda_schedule[each.key].name
  target_id = "${each.key}-target"
  arn       = aws_lambda_function.sports[each.key].arn
}

# ── Kinesis Stream (optional) ─────────────────────────────────────────────────
resource "aws_kinesis_stream" "live_stream" {
  provider    = aws.primary
  count       = var.enable_kinesis_stream ? 1 : 0
  name        = "${var.project_name}-live-stream"
  shard_count = 1
  tags        = local.tags
}
