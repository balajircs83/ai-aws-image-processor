# main.tf

# Provider configuration
provider "aws" {
  region = "us-east-1"
}

# S3 bucket for image storage
resource "aws_s3_bucket" "image_bucket" {
  bucket = "chatbot-image-processing-${random_string.suffix.result}"
}

# Random string for unique resource naming
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# IAM role for Lambda
resource "aws_iam_role" "lambda_exec" {
  name = "lambda_execution_role_${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# IAM policy for Lambda
resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda_policy_${random_string.suffix.result}"
  role = aws_iam_role.lambda_exec.id

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
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.image_bucket.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "rekognition:DetectFaces"
        ]
        Resource = "*"
      }
    ]
  })
}

# API Gateway
resource "aws_api_gateway_rest_api" "chatbot_api" {
  name        = "ChatbotAPI"
  description = "API for chatbot image processing"
}

resource "aws_api_gateway_resource" "image_resource" {
  rest_api_id = aws_api_gateway_rest_api.chatbot_api.id
  parent_id   = aws_api_gateway_rest_api.chatbot_api.root_resource_id
  path_part   = "image"
}

# POST Method
resource "aws_api_gateway_method" "post_method" {
  rest_api_id   = aws_api_gateway_rest_api.chatbot_api.id
  resource_id   = aws_api_gateway_resource.image_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.chatbot_api.id
  resource_id             = aws_api_gateway_resource.image_resource.id
  http_method             = aws_api_gateway_method.post_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.image_processor.invoke_arn
}

# OPTIONS Method for CORS Preflight
resource "aws_api_gateway_method" "options_method" {
  rest_api_id   = aws_api_gateway_rest_api.chatbot_api.id
  resource_id   = aws_api_gateway_resource.image_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_integration" {
  rest_api_id             = aws_api_gateway_rest_api.chatbot_api.id
  resource_id             = aws_api_gateway_resource.image_resource.id
  http_method             = aws_api_gateway_method.options_method.http_method
  type                    = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options_response_200" {
  rest_api_id = aws_api_gateway_rest_api.chatbot_api.id
  resource_id = aws_api_gateway_resource.image_resource.id
  http_method = aws_api_gateway_method.options_method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.chatbot_api.id
  resource_id = aws_api_gateway_resource.image_resource.id
  http_method = aws_api_gateway_method.options_method.http_method
  status_code = aws_api_gateway_method_response.options_response_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# Deployment
resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [
    aws_api_gateway_integration.lambda_integration,
    aws_api_gateway_integration.options_integration,
    aws_api_gateway_integration_response.options_integration_response
  ]
  rest_api_id = aws_api_gateway_rest_api.chatbot_api.id
  stage_name  = "prod"

  triggers = {
    redeployment = timestamp()
  }
}

output "api_endpoint" {
  value = "${aws_api_gateway_deployment.deployment.invoke_url}/image"
}

# Lambda function
resource "aws_lambda_function" "image_processor" {
  filename      = "lambda_function.zip"
  function_name = "imageProcessor_${random_string.suffix.result}"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  timeout       = 30

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.image_bucket.bucket
    }
  }
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.image_processor.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.chatbot_api.execution_arn}/*/*"
}

# S3 bucket for UI
resource "aws_s3_bucket" "ui_bucket" {
  bucket = "chatbot-ui-bucket-${random_string.suffix.result}"
}

resource "aws_s3_bucket_website_configuration" "ui_website" {
  bucket = aws_s3_bucket.ui_bucket.bucket

  index_document {
    suffix = "index.html"
  }
}

resource "aws_s3_bucket_policy" "ui_public_policy" {
  bucket = aws_s3_bucket.ui_bucket.bucket

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicRead"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.ui_bucket.arn}/*"
    }]
  })
}

resource "aws_s3_bucket_public_access_block" "ui_public_access" {
  bucket = aws_s3_bucket.ui_bucket.bucket

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

output "website_url" {
  value = "http://${aws_s3_bucket.ui_bucket.bucket}.s3-website-${aws_s3_bucket.ui_bucket.region}.amazonaws.com"
}