module "vpc" {
  source       = "../../../modules/vpc"
  project_name = "platform"
  vpc_cidr     = "10.1.0.0/16"
  public_subnets = [
    "10.1.1.0/24",
    "10.1.2.0/24",
    "10.1.3.0/24"
  ]
  private_app_subnets = [
    "10.1.11.0/24",
    "10.1.12.0/24",
    "10.1.13.0/24"
  ]
  private_db_subnets = [
    "10.1.21.0/24",
    "10.1.22.0/24",
    "10.1.23.0/24"
  ]
  azs = [
    "eu-central-1a",
    "eu-central-1b",
    "eu-central-1c"
  ]
  nat_gateway_count = 2
}

module "ecr" {
  source          = "../../../modules/ecr"
  repository_name = "platform-stage"
}

module "irsa" {
  source            = "../../../modules/irsa"
  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_issuer_url   = module.eks.cluster_oidc_issuer_url
}

module "eks" {
  source                  = "../../../modules/eks"
  cluster_name            = "platform-stage"
  kubernetes_version      = "1.33"
  private_subnet_ids      = module.vpc.private_app_subnet_ids
  node_instance_types     = ["t3.large"]
  desired_size            = 2
  min_size                = 1
  max_size                = 4
  ebs_csi_role_arn        = module.irsa.ebs_csi_role_arn
  github_actions_role_arn = module.irsa.github_actions_role_arn
}

module "security" {
  source       = "../../../modules/security"
  project_name = "platform"
  environment  = "stage"
}

module "secrets" {
  source       = "../../../modules/secrets"
  project_name = "platform"
  environment  = "stage"
  db_username  = "platform"
  db_password  = "stage-changeme456"
}
