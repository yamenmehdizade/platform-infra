output "vpc_id" {
  value = module.vpc.vpc_id
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "eks_cluster_oidc_issuer_url" {
  value = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "alb_controller_role_arn" {
  value = module.irsa.alb_controller_role_arn
}

output "cert_manager_role_arn" {
  value = module.irsa.cert_manager_role_arn
}

output "external_dns_role_arn" {
  value = module.irsa.external_dns_role_arn
}

output "ebs_csi_role_arn" {
  value = module.irsa.ebs_csi_role_arn
}

output "github_actions_role_arn" {
  value = module.irsa.github_actions_role_arn
}

output "waf_web_acl_arn" {
  value = module.security.waf_web_acl_arn
}

output "guardduty_detector_id" {
  value = module.security.guardduty_detector_id
}

output "db_secret_arn" {
  value = module.secrets.db_secret_arn
}

output "db_secret_name" {
  value = module.secrets.db_secret_name
}

output "external_secrets_role_arn" {
  value = module.irsa.external_secrets_role_arn
}


