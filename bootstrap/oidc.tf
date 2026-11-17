# GitHub Actions proves who it is with a short-lived OIDC token, and AWS hands back
# 1-hour credentials. No access keys are ever created, stored in GitHub, or rotated.

data "aws_caller_identity" "me" {}
data "aws_partition" "p" {}

locals {
  account = data.aws_caller_identity.me.account_id
  repo    = "${var.github_owner}/${var.github_repo}"
  issuer  = "token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_oidc_provider ? 1 : 0
  url            = "https://${local.issuer}"
  client_id_list = ["sts.amazonaws.com"]
  # AWS now validates GitHub's certificate itself and ignores these, but older providers still require the field.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://${local.issuer}"
}

locals {
  oidc_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

# Who may become which role. The "sub" claim is set by GitHub and can't be forged by a workflow:
#   pull requests and main-branch runs  -> plan role  (read-only: can look, can't change)
#   jobs in the "production" environment -> apply role (only after a human approves in GitHub)
data "aws_iam_policy_document" "trust_plan" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.issuer}:sub"
      values = [
        "repo:${local.repo}:pull_request",
        "repo:${local.repo}:ref:refs/heads/main",
      ]
    }
  }
}

data "aws_iam_policy_document" "trust_apply" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.issuer}:sub"
      values   = ["repo:${local.repo}:environment:production"]
    }
  }
}
