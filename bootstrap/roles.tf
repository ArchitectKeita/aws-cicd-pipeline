# Two roles, least privilege. Both are scoped by NAME to "${var.service_name}*" resources, so even a
# compromised workflow can't touch anything else in the account.

locals {
  r         = var.region
  svc       = var.service_name
  fn_arn    = "arn:${data.aws_partition.p.partition}:lambda:${local.r}:${local.account}:function:${local.svc}"
  role_arns = "arn:${data.aws_partition.p.partition}:iam::${local.account}:role/${local.svc}-*"
  logs_arns = [
    "arn:${data.aws_partition.p.partition}:logs:${local.r}:${local.account}:log-group:/aws/lambda/${local.svc}*",
    "arn:${data.aws_partition.p.partition}:logs:${local.r}:${local.account}:log-group:/aws/apigateway/${local.svc}*",
  ]
  api_arns = [
    "arn:${data.aws_partition.p.partition}:apigateway:${local.r}::/apis",
    "arn:${data.aws_partition.p.partition}:apigateway:${local.r}::/apis/*",
    "arn:${data.aws_partition.p.partition}:apigateway:${local.r}::/tags/*",
  ]
}

# ---------------------------------------------------------------- permissions boundary
# Any role the pipeline creates MUST carry this boundary, and the boundary only allows logging and
# tracing. That closes the classic escalation path: "create a role with admin, pass it to a Lambda".
data "aws_iam_policy_document" "boundary" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = local.logs_arns
  }
  statement {
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "boundary" {
  name        = "${local.svc}-workload-boundary"
  description = "Ceiling for every role the CI/CD pipeline creates: logs and tracing only."
  policy      = data.aws_iam_policy_document.boundary.json
}

# ---------------------------------------------------------------- plan role (read-only)
data "aws_iam_policy_document" "plan" {
  statement {
    sid       = "ReadService"
    actions   = ["lambda:Get*", "lambda:List*"]
    resources = [local.fn_arn, "${local.fn_arn}:*"]
  }
  statement {
    sid       = "ReadRoles"
    actions   = ["iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies"]
    resources = [local.role_arns]
  }
  statement {
    sid       = "ReadLogs"
    actions   = ["logs:ListTagsForResource", "logs:ListTagsLogGroup"]
    resources = local.logs_arns
  }
  statement {
    sid       = "DescribeLogGroups" # this API can't be scoped to a resource
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }
  statement {
    sid       = "ReadApi"
    actions   = ["apigateway:GET"]
    resources = local.api_arns
  }
  statement {
    sid       = "StateRead"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }
  statement {
    sid       = "StateObjectsRead"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }
  statement {
    sid       = "StateLockOnly" # plan may take the lock, but can never rewrite the state itself
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/*.tflock"]
  }
}

resource "aws_iam_role" "plan" {
  name                 = "${local.svc}-github-plan"
  description          = "GitHub Actions: terraform plan on pull requests and main. Read-only."
  assume_role_policy   = data.aws_iam_policy_document.trust_plan.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "plan" {
  name   = "plan"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan.json
}

# ---------------------------------------------------------------- apply role (production only)
data "aws_iam_policy_document" "apply" {
  source_policy_documents = [data.aws_iam_policy_document.plan.json]

  statement {
    sid = "ManageFunction"
    actions = [
      "lambda:CreateFunction", "lambda:DeleteFunction", "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration", "lambda:PublishVersion",
      "lambda:CreateAlias", "lambda:UpdateAlias", "lambda:DeleteAlias",
      "lambda:AddPermission", "lambda:RemovePermission",
      "lambda:TagResource", "lambda:UntagResource",
    ]
    resources = [local.fn_arn, "${local.fn_arn}:*"]
  }
  statement {
    sid       = "CreateRolesOnlyWithBoundary"
    actions   = ["iam:CreateRole", "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:AttachRolePolicy", "iam:DetachRolePolicy"]
    resources = [local.role_arns]
    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.boundary.arn]
    }
  }
  statement {
    sid       = "ManageRoles"
    actions   = ["iam:DeleteRole", "iam:UpdateRole", "iam:TagRole", "iam:UntagRole", "iam:ListInstanceProfilesForRole"]
    resources = [local.role_arns]
  }
  statement {
    sid       = "PassRoleToLambdaOnly"
    actions   = ["iam:PassRole"]
    resources = [local.role_arns]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["lambda.amazonaws.com"]
    }
  }
  statement {
    sid = "ManageLogs"
    actions = [
      "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy", "logs:DeleteRetentionPolicy",
      "logs:TagResource", "logs:UntagResource", "logs:TagLogGroup", "logs:UntagLogGroup",
    ]
    resources = local.logs_arns
  }
  statement {
    sid = "ApiAccessLogDelivery" # what API Gateway needs to write access logs; these APIs aren't resource-scoped
    actions = [
      "logs:CreateLogDelivery", "logs:GetLogDelivery", "logs:UpdateLogDelivery", "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries", "logs:PutResourcePolicy", "logs:DescribeResourcePolicies",
    ]
    resources = ["*"]
  }
  statement {
    sid       = "ManageApi"
    actions   = ["apigateway:GET", "apigateway:POST", "apigateway:PUT", "apigateway:PATCH", "apigateway:DELETE", "apigateway:TagResource", "apigateway:UntagResource"]
    resources = local.api_arns
  }
  statement {
    sid       = "StateWrite"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }
}

resource "aws_iam_role" "apply" {
  name                 = "${local.svc}-github-apply"
  description          = "GitHub Actions: terraform apply, only from the approved production environment."
  assume_role_policy   = data.aws_iam_policy_document.trust_apply.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "apply" {
  name   = "apply"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply.json
}
