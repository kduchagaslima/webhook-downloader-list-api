terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  profile = "sintegre"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# data "aws_cloudfront_cache_policy" "caching_optimized" {
#   name = "Managed-CachingOptimized"
# }

resource "aws_wafv2_web_acl" "downloads" {
  count = var.cloudfront_web_acl_id == "" ? 1 : 0
  name  = "${var.name_prefix}-downloads-web-acl"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-waf-common"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name_prefix}-downloads-web-acl"
    sampled_requests_enabled   = true
  }
}

# resource "aws_cognito_user_pool" "main" {
#   name = "${var.name_prefix}-user-pool"

#   password_policy {
#     minimum_length    = 8
#     require_lowercase = true
#     require_numbers   = true
#     require_symbols   = true
#     require_uppercase = true
#   }

#   admin_create_user_config {
#     allow_admin_create_user_only = true
#   }
# }

# resource "aws_cognito_user_pool_client" "main" {
#   name         = "${var.name_prefix}-app-client"
#   user_pool_id = aws_cognito_user_pool.main.id

#   generate_secret = false

#   explicit_auth_flows = [
#     "ALLOW_ADMIN_USER_PASSWORD_AUTH",
#     "ALLOW_USER_PASSWORD_AUTH",
#     "ALLOW_REFRESH_TOKEN_AUTH"
#   ]
# }

# resource "aws_cognito_user" "test_user" {
#   user_pool_id       = aws_cognito_user_pool.main.id
#   username           = var.cognito_test_username
#   temporary_password = var.cognito_test_temporary_password
#   message_action     = "SUPPRESS"
# }

resource "aws_sqs_queue" "webhook" {
  name = var.sqs_queue_name

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.webhook_dlq.arn
    maxReceiveCount     = var.sqs_max_receive_count
  })
}

resource "aws_sqs_queue" "webhook_dlq" {
  name = var.sqs_dlq_name
}

resource "aws_s3_bucket" "downloads" {
  bucket = var.s3_bucket_name
}

# locals {
#   cloudfront_key_dir          = "${path.module}/${var.cloudfront_key_dir}"
#   cloudfront_private_key_path = "${local.cloudfront_key_dir}/cloudfront_private_key.pem"
#   cloudfront_public_key_path  = "${local.cloudfront_key_dir}/cloudfront_public_key.pem"
#   cloudfront_public_key_pem   = var.cloudfront_public_key_pem != "" ? var.cloudfront_public_key_pem : file(local.cloudfront_public_key_path)
# }

# resource "null_resource" "cloudfront_keys" {
#   triggers = {
#     private_key_path = local.cloudfront_private_key_path
#     public_key_path  = local.cloudfront_public_key_path
#   }

#   provisioner "local-exec" {
#     command = <<EOT
# set -e
# mkdir -p "${local.cloudfront_key_dir}"
# if [ ! -f "${local.cloudfront_private_key_path}" ]; then
#   openssl genrsa -out "${local.cloudfront_private_key_path}" 2048
#   openssl rsa -pubout -in "${local.cloudfront_private_key_path}" -out "${local.cloudfront_public_key_path}"
# fi
# EOT
#   }
# }

# resource "aws_ssm_parameter" "cloudfront_private_key" {
#   name        = var.cloudfront_private_key_ssm_param
#   description = "CloudFront private key for signed cookies."
#   type        = "SecureString"
#   value       = file(local.cloudfront_private_key_path)

#   depends_on = [null_resource.cloudfront_keys]
# }

# resource "aws_cloudfront_origin_access_control" "downloads" {
#   name                              = "${var.name_prefix}-downloads-oac"
#   description                       = "OAC for private S3 downloads."
#   origin_access_control_origin_type = "s3"
#   signing_behavior                  = "always"
#   signing_protocol                  = "sigv4"
# }

# resource "aws_cloudfront_public_key" "signed_cookies" {
#   name        = "${var.name_prefix}-cf-public-key"
#   encoded_key = local.cloudfront_public_key_pem
#   comment     = "Public key for signed cookies."
# }

# resource "aws_cloudfront_key_group" "signed_cookies" {
#   name  = "${var.name_prefix}-cf-key-group"
#   items = [aws_cloudfront_public_key.signed_cookies.id]
# }

# resource "aws_cloudfront_distribution" "downloads" {
#   enabled = true
#   web_acl_id = var.cloudfront_web_acl_id != "" ? var.cloudfront_web_acl_id : aws_wafv2_web_acl.downloads[0].arn

#   origin {
#     domain_name              = aws_s3_bucket.downloads.bucket_regional_domain_name
#     origin_id                = "${var.name_prefix}-downloads-origin"
#     origin_access_control_id = aws_cloudfront_origin_access_control.downloads.id

#     s3_origin_config {
#       origin_access_identity = ""
#     }
#   }

#   default_cache_behavior {
#     target_origin_id       = "${var.name_prefix}-downloads-origin"
#     viewer_protocol_policy = "redirect-to-https"
#     allowed_methods        = ["GET", "HEAD"]
#     cached_methods         = ["GET", "HEAD"]
#     compress               = true
#     cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
#     trusted_key_groups     = [aws_cloudfront_key_group.signed_cookies.id]
#   }

#   restrictions {
#     geo_restriction {
#       restriction_type = "none"
#     }
#   }

#   viewer_certificate {
#     cloudfront_default_certificate = true
#   }
# }

# data "aws_iam_policy_document" "downloads_oac" {
#   statement {
#     sid     = "AllowCloudFrontServiceReadOnly"
#     actions = ["s3:GetObject"]
#     resources = [
#       "${aws_s3_bucket.downloads.arn}/*"
#     ]

#     principals {
#       type        = "Service"
#       identifiers = ["cloudfront.amazonaws.com"]
#     }

#     condition {
#       test     = "StringEquals"
#       variable = "AWS:SourceArn"
#       values   = [aws_cloudfront_distribution.downloads.arn]
#     }
#   }
# }

# resource "aws_s3_bucket_policy" "downloads" {
#   bucket = aws_s3_bucket.downloads.id
#   policy = data.aws_iam_policy_document.downloads_oac.json
# }

resource "aws_iam_role" "lambda" {
  name = "${var.name_prefix}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda" {
  name = "${var.name_prefix}-lambda-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.downloads.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = [
          aws_sqs_queue.webhook.arn,
          aws_sqs_queue.webhook_dlq.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role" "lambda_api" {
  name = "${var.name_prefix}-lambda-api-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_api" {
  name = "${var.name_prefix}-lambda-api-policy"
  role = aws_iam_role.lambda_api.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.downloads.arn
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter"
        ]
        Resource = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/${trim(var.cloudfront_private_key_ssm_param, "/")}"
      }
    ]
  })
}

# resource "aws_iam_role" "lambda_authorizer" {
#   name = "${var.name_prefix}-lambda-authorizer-role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRole"
#         Effect = "Allow"
#         Principal = {
#           Service = "lambda.amazonaws.com"
#         }
#       }
#     ]
#   })
# }

# resource "aws_iam_role_policy" "lambda_authorizer" {
#   name = "${var.name_prefix}-lambda-authorizer-policy"
#   role = aws_iam_role.lambda_authorizer.id

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Action = [
#           "logs:CreateLogGroup",
#           "logs:CreateLogStream",
#           "logs:PutLogEvents"
#         ]
#         Resource = "*"
#       },
#       {
#         Effect = "Allow"
#         Action = [
#           "cognito-idp:GetUser"
#         ]
#         Resource = "*"
#       }
#     ]
#   })
# }

data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

# data "archive_file" "lambda_list" {
#   type        = "zip"
#   source_dir  = "${path.module}/lambda_list"
#   output_path = "${path.module}/lambda_list.zip"
# }

# data "archive_file" "lambda_authorizer" {
#   type        = "zip"
#   source_dir  = "${path.module}/lambda_authorizer"
#   output_path = "${path.module}/lambda_authorizer.zip"
# }

# data "archive_file" "lambda_dlq" {
#   type        = "zip"
#   source_dir  = "${path.module}/lambda_dlq"
#   output_path = "${path.module}/lambda_dlq.zip"
# }

resource "aws_lambda_function" "download" {
  function_name = "${var.name_prefix}-download"
  role          = aws_iam_role.lambda.arn
  handler       = "main.handler"
  runtime       = "python3.12"

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.downloads.bucket
    }
  }

  timeout = 30
}

# resource "aws_lambda_function" "list_by_product" {
#   function_name = "${var.name_prefix}-list-by-product"
#   role          = aws_iam_role.lambda_api.arn
#   handler       = "main.handler"
#   runtime       = "python3.12"

#   filename         = data.archive_file.lambda_list.output_path
#   source_code_hash = data.archive_file.lambda_list.output_base64sha256

#   environment {
#     variables = {
#       BUCKET_NAME                = aws_s3_bucket.downloads.bucket
#       CF_DOMAIN                  = aws_cloudfront_distribution.downloads.domain_name
#       CF_KEY_PAIR_ID             = aws_cloudfront_public_key.signed_cookies.id
#       CF_PRIVATE_KEY_PARAM       = var.cloudfront_private_key_ssm_param
#       COOKIE_TTL_SECONDS         = tostring(var.cloudfront_cookie_ttl_seconds)
#       S3_PREFIX_TEMPLATE         = var.s3_prefix_template
#     }
#   }

#   timeout = 30
# }

# resource "aws_lambda_function" "authorizer" {
#   function_name = "${var.name_prefix}-authorizer"
#   role          = aws_iam_role.lambda_authorizer.arn
#   handler       = "main.handler"
#   runtime       = "python3.12"

#   filename         = data.archive_file.lambda_authorizer.output_path
#   source_code_hash = data.archive_file.lambda_authorizer.output_base64sha256

#   timeout = 10
# }

# resource "aws_lambda_function" "dlq_processor" {
#   function_name = "${var.name_prefix}-dlq-processor"
#   role          = aws_iam_role.lambda.arn
#   handler       = "main.handler"
#   runtime       = "python3.12"

#   filename         = data.archive_file.lambda_dlq.output_path
#   source_code_hash = data.archive_file.lambda_dlq.output_base64sha256

#   environment {
#     variables = {
#       BUCKET_NAME = aws_s3_bucket.downloads.bucket
#       DLQ_URL     = aws_sqs_queue.webhook_dlq.url
#     }
#   }

#   timeout = 60
# }

resource "aws_lambda_event_source_mapping" "sqs" {
  event_source_arn = aws_sqs_queue.webhook.arn
  function_name    = aws_lambda_function.download.arn
  batch_size       = 10
}

resource "aws_iam_role" "apigw" {
  name = "${var.name_prefix}-apigw-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "apigw" {
  name = "${var.name_prefix}-apigw-policy"
  role = aws_iam_role.apigw.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.webhook.arn
      }
    ]
  })
}

resource "aws_api_gateway_rest_api" "webhook" {
  name = "${var.name_prefix}-webhook"
}

resource "aws_api_gateway_resource" "webhook" {
  rest_api_id = aws_api_gateway_rest_api.webhook.id
  parent_id   = aws_api_gateway_rest_api.webhook.root_resource_id
  path_part   = "webhook"
}

# resource "aws_api_gateway_resource" "produtos" {
#   rest_api_id = aws_api_gateway_rest_api.webhook.id
#   parent_id   = aws_api_gateway_rest_api.webhook.root_resource_id
#   path_part   = "produtos"
# }

# resource "aws_api_gateway_resource" "produtos_tipo" {
#   rest_api_id = aws_api_gateway_rest_api.webhook.id
#   parent_id   = aws_api_gateway_resource.produtos.id
#   path_part   = "{tipo}"
# }

# resource "aws_api_gateway_resource" "produtos_arquivos" {
#   rest_api_id = aws_api_gateway_rest_api.webhook.id
#   parent_id   = aws_api_gateway_resource.produtos_tipo.id
#   path_part   = "arquivos"
# }

# resource "aws_api_gateway_authorizer" "cognito_lambda" {
#   name                   = "${var.name_prefix}-cognito-authorizer"
#   rest_api_id            = aws_api_gateway_rest_api.webhook.id
#   authorizer_uri         = "arn:aws:apigateway:${data.aws_region.current.name}:lambda:path/2015-03-31/functions/${aws_lambda_function.authorizer.arn}/invocations"
#   type                   = "TOKEN"
#   identity_source        = "method.request.header.Authorization"
#   authorizer_result_ttl_in_seconds = 300
# }

# resource "aws_api_gateway_method" "produtos_arquivos_get" {
#   rest_api_id   = aws_api_gateway_rest_api.webhook.id
#   resource_id   = aws_api_gateway_resource.produtos_arquivos.id
#   http_method   = "GET"
#   authorization = "CUSTOM"
#   authorizer_id = aws_api_gateway_authorizer.cognito_lambda.id

#   request_parameters = {
#     "method.request.path.tipo" = true
#   }
# }

# resource "aws_api_gateway_integration" "produtos_arquivos_lambda" {
#   rest_api_id = aws_api_gateway_rest_api.webhook.id
#   resource_id = aws_api_gateway_resource.produtos_arquivos.id
#   http_method = aws_api_gateway_method.produtos_arquivos_get.http_method

#   integration_http_method = "POST"
#   type                    = "AWS_PROXY"
#   uri                     = aws_lambda_function.list_by_product.invoke_arn
# }

resource "aws_api_gateway_method" "webhook_post" {
  rest_api_id   = aws_api_gateway_rest_api.webhook.id
  resource_id   = aws_api_gateway_resource.webhook.id
  http_method   = "POST"
  authorization = "NONE"
}

# resource "aws_lambda_permission" "apigw_list" {
#   statement_id  = "AllowApiGatewayInvokeListByProduct"
#   action        = "lambda:InvokeFunction"
#   function_name = aws_lambda_function.list_by_product.function_name
#   principal     = "apigateway.amazonaws.com"
#   source_arn    = "${aws_api_gateway_rest_api.webhook.execution_arn}/*/GET/produtos/*/arquivos"
# }

# resource "aws_lambda_permission" "apigw_authorizer" {
#   statement_id  = "AllowApiGatewayInvokeAuthorizer"
#   action        = "lambda:InvokeFunction"
#   function_name = aws_lambda_function.authorizer.function_name
#   principal     = "apigateway.amazonaws.com"
#   source_arn    = "${aws_api_gateway_rest_api.webhook.execution_arn}/authorizers/*"
# }

resource "aws_api_gateway_integration" "webhook_sqs" {
  rest_api_id = aws_api_gateway_rest_api.webhook.id
  resource_id = aws_api_gateway_resource.webhook.id
  http_method = aws_api_gateway_method.webhook_post.http_method

  type                    = "AWS"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:sqs:path/${data.aws_caller_identity.current.account_id}/${aws_sqs_queue.webhook.name}"
  credentials             = aws_iam_role.apigw.arn

  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }

  request_templates = {
    "application/json" = "Action=SendMessage&MessageBody=$util.urlEncode($input.body)"
  }
}

resource "aws_api_gateway_method_response" "webhook_post_200" {
  rest_api_id = aws_api_gateway_rest_api.webhook.id
  resource_id = aws_api_gateway_resource.webhook.id
  http_method = aws_api_gateway_method.webhook_post.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "webhook_post_200" {
  rest_api_id = aws_api_gateway_rest_api.webhook.id
  resource_id = aws_api_gateway_resource.webhook.id
  http_method = aws_api_gateway_method.webhook_post.http_method
  status_code = aws_api_gateway_method_response.webhook_post_200.status_code

  response_templates = {
    "application/json" = "{\"status\":\"ok\"}"
  }

  depends_on = [
    aws_api_gateway_integration.webhook_sqs,
    aws_api_gateway_method_response.webhook_post_200
  ]
}

resource "aws_api_gateway_deployment" "webhook" {
  rest_api_id = aws_api_gateway_rest_api.webhook.id

  triggers = {
    redeploy = sha1(jsonencode([
      aws_api_gateway_resource.webhook.id,
      aws_api_gateway_method.webhook_post.id,
      aws_api_gateway_integration.webhook_sqs.id,
      aws_api_gateway_method_response.webhook_post_200.id,
      aws_api_gateway_integration_response.webhook_post_200.id
      # aws_api_gateway_resource.produtos.id,
      # aws_api_gateway_resource.produtos_tipo.id,
      # aws_api_gateway_resource.produtos_arquivos.id,
      # aws_api_gateway_method.produtos_arquivos_get.id,
      # aws_api_gateway_integration.produtos_arquivos_lambda.id,
      # aws_api_gateway_authorizer.cognito_lambda.id
    ]))
  }

  depends_on = [
    aws_api_gateway_integration.webhook_sqs,
    aws_api_gateway_integration_response.webhook_post_200
    # aws_api_gateway_integration.produtos_arquivos_lambda
  ]
}

resource "aws_api_gateway_stage" "webhook" {
  rest_api_id   = aws_api_gateway_rest_api.webhook.id
  deployment_id = aws_api_gateway_deployment.webhook.id
  stage_name    = var.api_stage_name
}
