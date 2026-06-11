data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket  = "yamen-platform-tfstate-028185488284"
    key     = "prod/infra/terraform.tfstate"
    region  = "eu-central-1"
    encrypt = true
  }
}

data "aws_eks_cluster" "this" {
  name = data.terraform_remote_state.infra.outputs.eks_cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = data.terraform_remote_state.infra.outputs.eks_cluster_name
}

module "argocd" {
  source = "../../../modules/argocd"
}
