output "alb_controller_role_arn" {
  value = aws_iam_role.alb_controller.arn
}

output "cert_manager_role_arn" {
  value = aws_iam_role.cert_manager.arn
}

output "external_dns_role_arn" {
  value = aws_iam_role.external_dns.arn
}

output "ebs_csi_role_arn" {
  value = aws_iam_role.ebs_csi.arn
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}

output "external_secrets_role_arn" {
  value = aws_iam_role.external_secrets.arn
}
