# Configure the Terraform Enterprise Provider
provider "tfe" {
  hostname = var.tfe_hostname
  token    = var.tfe_token
  version  = ">= 0.23.0"
}

module "example" {
  source = "../../"

  config_file_path    = "./stacks"
  config_file_pattern = "uw2-testing.yaml"
  organization        = var.organization

  vcs_repo = {
    branch             = var.branch
    identifier         = var.identifier
    ingress_submodules = var.ingress_submodules
    oauth_token_id     = var.oauth_token_id
  }
}
