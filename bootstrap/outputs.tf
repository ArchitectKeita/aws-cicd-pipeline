# Paste these three into GitHub: repo Settings -> Secrets and variables -> Actions -> Variables.
# They are identifiers, not secrets: without GitHub's signed token, nobody can assume these roles.
output "AWS_PLAN_ROLE_ARN" {
  value = aws_iam_role.plan.arn
}

output "AWS_APPLY_ROLE_ARN" {
  value = aws_iam_role.apply.arn
}

output "TF_STATE_BUCKET" {
  value = aws_s3_bucket.state.bucket
}

output "BOUNDARY_POLICY_ARN" {
  value = aws_iam_policy.boundary.arn
}

output "gh_commands" {
  description = "Or set all of them in one go with the GitHub CLI."
  value       = <<-EOT
    gh variable set AWS_PLAN_ROLE_ARN   --repo ${local.repo} --body "${aws_iam_role.plan.arn}"
    gh variable set AWS_APPLY_ROLE_ARN  --repo ${local.repo} --body "${aws_iam_role.apply.arn}"
    gh variable set TF_STATE_BUCKET     --repo ${local.repo} --body "${aws_s3_bucket.state.bucket}"
    gh variable set BOUNDARY_POLICY_ARN --repo ${local.repo} --body "${aws_iam_policy.boundary.arn}"
  EOT
}
