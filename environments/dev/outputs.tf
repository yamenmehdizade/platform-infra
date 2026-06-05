output "vpc_id" {
  value = module.vpc.vpc_id
}

output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
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
