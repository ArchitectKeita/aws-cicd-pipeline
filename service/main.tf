# The service: one Lambda, published as an immutable version per deploy, served through a "live" alias
# behind an HTTP API. Rolling back = pointing "live" at the previous version (seconds, no rebuild).

locals {
  svc = var.service_name
}

data "archive_file" "code" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/.build/app.zip"
  excludes    = ["__pycache__"]
}

# ---------------------------------------------------------------- identity
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "fn" {
  name                 = "${local.svc}-lambda"
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  permissions_boundary = var.boundary_arn
}

data "aws_iam_policy_document" "fn" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.fn.arn}:*"]
  }
  statement {
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"] # X-Ray doesn't support resource-level permissions
  }
}

resource "aws_iam_role_policy" "fn" {
  name   = "runtime"
  role   = aws_iam_role.fn.id
  policy = data.aws_iam_policy_document.fn.json
}

# ---------------------------------------------------------------- function
resource "aws_cloudwatch_log_group" "fn" {
  # checkov:skip=CKV_AWS_158: Logs hold only request metadata; AWS-managed encryption is sufficient.
  name              = "/aws/lambda/${local.svc}"
  retention_in_days = 365
}

resource "aws_lambda_function" "fn" {
  # checkov:skip=CKV_AWS_117: Calls no private resources, so a VPC would add cost and cold starts for nothing.
  # checkov:skip=CKV_AWS_116: Invoked synchronously by API Gateway; a dead-letter queue only applies to async calls.
  # checkov:skip=CKV_AWS_115: Reserved concurrency would eat into a new account's 10-execution pool; API Gateway throttles instead.
  # checkov:skip=CKV_AWS_272: Code signing is replaced by the pipeline itself: only reviewed, tested commits reach this function.
  # checkov:skip=CKV_AWS_173: Environment variables hold no secrets (commit, version, a demo flag).
  function_name    = local.svc
  role             = aws_iam_role.fn.arn
  runtime          = "python3.12"
  handler          = "app.handler"
  filename         = data.archive_file.code.output_path
  source_code_hash = data.archive_file.code.output_base64sha256
  memory_size      = 128
  timeout          = 5
  publish          = true # every deploy becomes an immutable, numbered version

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      SERVICE_NAME        = local.svc
      APP_VERSION         = var.app_version
      COMMIT_SHA          = var.commit_sha
      SIMULATE_BAD_DEPLOY = tostring(var.simulate_bad_deploy)
    }
  }

  depends_on = [aws_cloudwatch_log_group.fn, aws_iam_role_policy.fn]
}

resource "aws_lambda_alias" "live" {
  name             = "live"
  function_name    = aws_lambda_function.fn.function_name
  function_version = aws_lambda_function.fn.version
}

# ---------------------------------------------------------------- HTTP API
resource "aws_apigatewayv2_api" "http" {
  name          = local.svc
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "fn" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_alias.live.invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 6000
}

resource "aws_apigatewayv2_route" "routes" {
  # checkov:skip=CKV_AWS_309: A public status page by design; throttling below caps abuse.
  for_each  = toset(["GET /", "GET /health"])
  api_id    = aws_apigatewayv2_api.http.id
  route_key = each.value
  target    = "integrations/${aws_apigatewayv2_integration.fn.id}"
}

resource "aws_cloudwatch_log_group" "api" {
  # checkov:skip=CKV_AWS_158: Access logs hold only request metadata; AWS-managed encryption is sufficient.
  name              = "/aws/apigateway/${local.svc}"
  retention_in_days = 365
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 20
    throttling_rate_limit  = 10
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api.arn
    format = jsonencode({
      requestId = "$context.requestId", ip = "$context.identity.sourceIp", route = "$context.routeKey",
      status    = "$context.status", latencyMs = "$context.responseLatency", time = "$context.requestTime"
    })
  }
}

resource "aws_lambda_permission" "api" {
  statement_id  = "AllowHttpApi"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fn.function_name
  qualifier     = aws_lambda_alias.live.name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}
