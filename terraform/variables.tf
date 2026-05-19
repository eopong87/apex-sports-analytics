variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "apex-sports-analytics"
}

variable "environment" {
  description = "Environment tag"
  type        = string
  default     = "portfolio"
}

variable "bucket_prefix" {
  description = "Globally unique S3 bucket name prefix"
  type        = string
  validation {
    condition     = length(var.bucket_prefix) >= 3 && length(var.bucket_prefix) <= 47
    error_message = "bucket_prefix must be between 3 and 47 characters."
  }
}

variable "primary_region" {
  description = "Primary AWS region"
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "Secondary AWS region for disaster recovery"
  type        = string
  default     = "us-west-2"
}

variable "enable_route53_failover" {
  description = "Enable Route 53 health check and failover DNS"
  type        = bool
  default     = false
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Domain name for Route 53 failover record"
  type        = string
  default     = ""
}

variable "enable_backend" {
  description = "Deploy Lambda, API Gateway, DynamoDB, and Secrets Manager"
  type        = bool
  default     = true
}

variable "enable_eventbridge_schedules" {
  description = "Enable EventBridge scheduled Lambda invocations"
  type        = bool
  default     = false
}

variable "enable_kinesis_stream" {
  description = "Enable Kinesis real-time stream"
  type        = bool
  default     = false
}
