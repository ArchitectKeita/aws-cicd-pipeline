output "url" {
  value = aws_apigatewayv2_api.http.api_endpoint
}

output "function_name" {
  value = aws_lambda_function.fn.function_name
}

output "live_version" {
  value = aws_lambda_alias.live.function_version
}
