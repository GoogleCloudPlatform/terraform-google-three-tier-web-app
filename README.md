# terraform-google-three-tier-app

This module was generated from [terraform-google-module-template](https://github.com/terraform-google-modules/terraform-google-module-template/), which by default generates a module that simply creates a GCS bucket. As the module develops, this README should be updated.

The resources/services/activations/deletions that this module will create/trigger are:

- Create a GCS bucket with the provided name

## Usage

Basic usage of this module is as follows:

```hcl
module "three_tier_app" {
  source  = "terraform-google-modules/three-tier-app/google"
  version = "~> 0.1"

  project_id  = var.project_id
  region = "us-central1"
  zone = "us-central1-a"
}
```

Functional examples are included in the
[examples](./examples/) directory.

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| deployment\_name | The name of this particular deployment, will get added as a prefix to most resources. | `string` | `"three-tier-app"` | no |
| enable\_apis | Whether or not to enable underlying apis in this solution. . | `string` | `true` | no |
| labels | A map of labels to apply to contained resources. | `map(string)` | <pre>{<br>  "three-tier-app": true<br>}</pre> | no |
| project\_id | The project ID to deploy to | `any` | n/a | yes |
| region | The Compute Region to deploy to | `string` | n/a | yes |
| run\_roles\_list | The list of roles that run needs | `list(string)` | <pre>[<br>  "roles/cloudsql.instanceUser",<br>  "roles/cloudsql.client"<br>]</pre> | no |
| zone | The Compute Zonbe to deploy to | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| endpoint | The url of the front end which we want to surface to the user |
| sqlservername | The name of the database that we randomly generated. |

<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->

## Requirements

These sections describe requirements for using this module.

### Software

The following dependencies must be available:

- [Terraform][terraform] v0.13
- [Terraform Provider for GCP][terraform-provider-gcp] plugin v3.0

### Service Account

A service account with the following roles must be used to provision
the resources of this module:

- Storage Admin: `roles/storage.admin`

The [Project Factory module][project-factory-module] and the
[IAM module][iam-module] may be used in combination to provision a
service account with the necessary roles applied.

### APIs

A project with the following APIs enabled must be used to host the
resources of this module:

- Google Cloud Storage JSON API: `storage-api.googleapis.com`

The [Project Factory module][project-factory-module] can be used to
provision a project with the necessary APIs enabled.

## Contributing

Refer to the [contribution guidelines](./CONTRIBUTING.md) for
information on contributing to this module.

[iam-module]: https://registry.terraform.io/modules/terraform-google-modules/iam/google
[project-factory-module]: https://registry.terraform.io/modules/terraform-google-modules/project-factory/google
[terraform-provider-gcp]: https://www.terraform.io/docs/providers/google/index.html
[terraform]: https://www.terraform.io/downloads.html

## Security Disclosures

Please see our [security disclosure process](./SECURITY.md).
