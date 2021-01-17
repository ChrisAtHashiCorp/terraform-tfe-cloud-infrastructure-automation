locals {
  // Use the provided config file path or default to the current dir
  config_file_path = coalesce(var.config_file_path, path.cwd)

  // Result ex: [gbl-audit.yaml, gbl-auto.yaml, gbl-dev.yaml, ...]
  config_filenames = fileset(local.config_file_path, var.config_file_pattern)
}

module "config_files" {
  source   = "git::https://github.com/cloudposse/terraform-yaml-config.git?ref=main"
  for_each = local.config_filenames

  context = module.this.context

  map_config_local_base_path = local.config_file_path
  map_config_paths           = [each.value]
}

locals {
  // Result ex: [gbl-audit, gbl-auto, gbl-dev, ...]
  config_files = { for f in keys(module.config_files) : trimsuffix(basename(f), ".yaml") => module.config_files[f] }
  // Result ex: { gbl-audit = { globals = { ... }, terraform = { project1 = { vars = ... }, project2 = { vars = ... } } } }
  projects = {
    for f in keys(local.config_files) : f => {
      "compoonents" = lookup(lookup(local.config_files[f].map_configs, "components", {}), "terraform", {}),
      "triggers" = lookup(local.config_files[f], "all_imports_list", [])
    }
  }

  project_workspaces = merge([
    for k, v in module.tfc_environment : {
      for env, config in v.projects :
      "${k}-${env}" => config
    }
  ]...)

  custom_triggers = merge({}, flatten([
    for k, v in local.projects : [
      for project, settings in v.terraform : {
        for trigger in(try(settings.triggers, null) != null ? settings.triggers : []) :
        "${k}-${project}-${trigger}" => {
          source      = trigger
          destination = "${k}-${project}"
        } if try(settings.workspace_enabled, false)
      }
    ]
  ])...)
}

output "config" {
  value = module.config_files
}

output "config_files" {
  value = local.config_file_path
}

output "projects" {
  value = local.projects
}

# output "project_workspaces" {
#   value = local.project_workspaces
# }

# output "environment_workspaces" {
#   value = local.environment_workspaces
# }

# Create our top-level workspace
module "tfc_config" {
  source = "./modules/workspaces"

  auto_apply            = var.config_auto_apply
  file_triggers_enabled = true
  name                  = var.top_level_workspace
  organization          = var.organization
  terraform_version     = var.terraform_version
  trigger_prefixes      = [basename(local.config_file_path)]
  vcs_repo              = var.vcs_repo
  working_directory     = "${var.projects_path}/${var.tfc_project_path}"
  execution_mode        = "remote"
}

# Create our 2nd-tier environment workspaces, as well as our 3rd-tier project workspaces
# module "tfc_environment" {
#   source = "./modules/environment"

#   for_each = local.projects

#   config_name       = each.key
#   global_values     = each.value.globals
#   terraform_version = var.terraform_version
#   projects          = local.projects[each.key].terraform
#   projects_path     = var.projects_path
#   organization      = var.organization
#   vcs_repo          = var.vcs_repo
# }

# # Generate our custom triggers based on configuration defined in YAML (at the project level)
# resource "tfe_run_trigger" "this" {
#   for_each = local.custom_triggers

#   # We link the trigger to another 3rd tier project workspace, OR a 2nd tier environment workspace
#   workspace_id  = local.project_workspaces[each.value.destination].workspace.id
#   sourceable_id = try(local.project_workspaces[each.value.source].workspace.id, local.environment_workspaces[each.value.source].workspace.id)
# }
