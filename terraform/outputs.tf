output "api_invoke_url" {
  description = "Invoke URL for the webhook endpoint."
  value       = "${aws_api_gateway_stage.webhook.invoke_url}/webhook"
}

# output "api_list_by_product_url" {
#   description = "Invoke URL for listing by product."
#   value       = "${aws_api_gateway_stage.webhook.invoke_url}/produtos/{tipo}/arquivos"
# }

# output "cloudfront_domain" {
#   description = "CloudFront distribution domain for downloads."
#   value       = aws_cloudfront_distribution.downloads.domain_name
# }

# output "cloudfront_web_acl_arn" {
#   description = "WAFv2 Web ACL ARN used by the CloudFront distribution."
#   value       = var.cloudfront_web_acl_id != "" ? var.cloudfront_web_acl_id : aws_wafv2_web_acl.downloads[0].arn
# }

# output "cognito_user_pool_id" {
#   description = "Cognito User Pool ID."
#   value       = aws_cognito_user_pool.main.id
# }

# output "cognito_user_pool_client_id" {
#   description = "Cognito User Pool App Client ID."
#   value       = aws_cognito_user_pool_client.main.id
# }

# output "cognito_test_username" {
#   description = "Cognito test username."
#   value       = var.cognito_test_username
# }

output "sqs_queue_url" {
  description = "SQS queue URL."
  value       = aws_sqs_queue.webhook.url
}

output "sqs_dlq_url" {
  description = "DLQ SQS queue URL."
  value       = aws_sqs_queue.webhook_dlq.url
}

# output "dlq_processor_lambda_name" {
#   description = "Lambda function name for DLQ processing."
#   value       = aws_lambda_function.dlq_processor.function_name
# }

output "s3_bucket_name" {
  description = "S3 bucket used for downloads."
  value       = aws_s3_bucket.downloads.bucket
}
