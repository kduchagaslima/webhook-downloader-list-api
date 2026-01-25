variable "aws_region" {
  type        = string
  description = "AWS region to deploy to."
  default     = "us-east-1"
}

variable "name_prefix" {
  type        = string
  description = "Prefix for resource names."
  default     = "webhook"
}

variable "sqs_queue_name" {
  type        = string
  description = "SQS queue name for webhook messages."
  default     = "webhook-queue"
}

variable "sqs_dlq_name" {
  type        = string
  description = "SQS queue name for the webhook dead-letter queue."
  default     = "webhook-dlq"
}

variable "sqs_max_receive_count" {
  type        = number
  description = "Number of receives before sending a message to the DLQ."
  default     = 5
}

variable "s3_bucket_name" {
  type        = string
  description = "S3 bucket name to store downloaded files. Must be globally unique."
  default = "sintegre-files"
}

variable "cloudfront_public_key_pem" {
  type        = string
  description = "PEM-encoded CloudFront public key for signed cookies."
  default     = ""
}

variable "cloudfront_key_dir" {
  type        = string
  description = "Directory under the module to store generated CloudFront keys."
  default     = "keys"
}

variable "cloudfront_private_key_ssm_param" {
  type        = string
  description = "SSM SecureString parameter name containing the CloudFront private key PEM."
  default     = "/webhook/cloudfront/private-key"
}

variable "cloudfront_cookie_ttl_seconds" {
  type        = number
  description = "Signed cookie TTL in seconds."
  default     = 900
}

variable "cloudfront_web_acl_id" {
  type        = string
  description = "WAFv2 Web ACL ARN required for CloudFront distribution."
  default     = "arn:aws:wafv2:us-east-1:974307046314:global/webacl/CreatedByCloudFront-c26fc0d2/fcc39afa-e114-418b-a3a3-461d94424793"
}

variable "s3_prefix_template" {
  type        = string
  description = "Template for prefix generation, supports {product} and {date}."
  default     = "{date}/{product}"
}

variable "api_stage_name" {
  type        = string
  description = "API Gateway stage name."
  default     = "prod"
}

variable "cognito_test_username" {
  type        = string
  description = "Username for the Cognito test user."
  default     = "test.user@example.com"
}

variable "cognito_test_temporary_password" {
  type        = string
  description = "Temporary password for the Cognito test user."
  default     = "Temp#1234"
  sensitive   = true
}
