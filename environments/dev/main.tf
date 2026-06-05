module "vpc" {
  source = "../../modules/vpc"

  project_name = "platform"

  vpc_cidr = "10.0.0.0/16"

  public_subnets = [
    "10.0.1.0/24",
    "10.0.2.0/24",
    "10.0.3.0/24"
  ]

  private_app_subnets = [
    "10.0.11.0/24",
    "10.0.12.0/24",
    "10.0.13.0/24"
  ]

  private_db_subnets = [
    "10.0.21.0/24",
    "10.0.22.0/24",
    "10.0.23.0/24"
  ]

  azs = [
    "eu-central-1a",
    "eu-central-1b",
    "eu-central-1c"
  ]

  nat_gateway_count = 1
}

module "ecr" {
  source = "../../modules/ecr"

  repository_name = "platform-dev"
}

module "eks" {
  source = "../../modules/eks"

  cluster_name       = "platform-dev"
  kubernetes_version = "1.33"

  private_subnet_ids = module.vpc.private_app_subnet_ids


  node_instance_types = ["t3.medium"]

  desired_size = 2
  min_size     = 1
  max_size     = 3
}

module "irsa" {
  source = "../../modules/irsa"

  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_issuer_url   = module.eks.cluster_oidc_issuer_url
}

module "argocd" {
  source = "../../modules/argocd"

  depends_on = [module.eks]
}
