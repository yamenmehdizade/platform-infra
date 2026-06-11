module "vpc" {
  source       = "../../../modules/vpc"
  project_name = "platform"
  vpc_cidr     = "10.2.0.0/16"
  public_subnets = [
    "10.2.1.0/24",
    "10.2.2.0/24",
    "10.2.3.0/24"
  ]
  private_app_subnets = [
    "10.2.11.0/24",
    "10.2.12.0/24",
    "10.2.13.0/24"
  ]
  private_db_subnets = [
    "10.2.21.0/24",
    "10.2.22.0/24",
    "10.2.23.0/24"
  ]
  azs = [
    "eu-central-1a",
    "eu-central-1b",
    "eu-central-1c"
  ]
  nat_gateway_count = 3
}

module "ecr" {
  source          = "../../../modules/ecr"
  repository_name = "platform-prod"
}

module "irsa" {
  source            = "../../../modules/irsa"
  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_issuer_url   = module.eks.cluster_oidc_issuer_url
}

module "eks" {
  source                  = "../../../modules/eks"
  cluster_name            = "platform-prod"
  kubernetes_version      = "1.33"
  private_subnet_ids      = module.vpc.private_app_subnet_ids
  node_instance_types     = ["m5.xlarge"]
  desired_size            = 3
  min_size                = 2
  max_size                = 10
  ebs_csi_role_arn        = module.irsa.ebs_csi_role_arn
  github_actions_role_arn = module.irsa.github_actions_role_arn
}

module "security" {
  source       = "../../../modules/security"
  project_name = "platform"
  environment  = "prod"
}

module "secrets" {
  source       = "../../../modules/secrets"
  project_name = "platform"
  environment  = "prod"
  db_username  = "platform"
  db_password  = "prod-changeme789"
}








