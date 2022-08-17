/**
 * Copyright 2021 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

data "google_project" "project" {
  project_id = var.project_id
}

module "sql-db" {
  source  = "GoogleCloudPlatform/sql-db/google//modules/mysql"
  version = "8.0.0"
}

# TODO: DELETE if passes test. 
# provider "google" {
#   project = var.project_id
#   region  = var.region
#   zone    = var.zone
# }


locals {
  sabuild   = "${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
  api_image = "gcr.io/sic-container-repo/todo-api"
  fe_image  = "gcr.io/sic-container-repo/todo-fe"
}


module "project-services" {
  source                      = "terraform-google-modules/project-factory/google//modules/project_services"
  version                     = "13.0.0"
  disable_services_on_destroy = false

  project_id  = var.project_id
  enable_apis = var.enable_apis

  activate_apis = [
    "compute.googleapis.com",
    "cloudapis.googleapis.com",
    "vpcaccess.googleapis.com",
    "servicenetworking.googleapis.com",
    "cloudbuild.googleapis.com",
    "sql-component.googleapis.com",
    "sqladmin.googleapis.com",
    "storage.googleapis.com",
    "secretmanager.googleapis.com",
    "run.googleapis.com",
    "redis.googleapis.com",
  ]
}

# TODO: See if this can be modularized
# Handle Permissions
variable "build_roles_list" {
  description = "The list of roles that build needs for"
  type        = list(string)
  default = [
    "roles/run.developer",
    "roles/vpaccess.user",
    "roles/iam.serviceAccountUser",
    "roles/run.admin",
    "roles/secretmanager.secretAccessor",
  ]
}

resource "google_project_iam_member" "allbuild" {
  for_each   = toset(var.build_roles_list)
  project    = data.google_project.project.number
  role       = each.key
  member     = "serviceAccount:${local.sabuild}"
  depends_on = [module.project-services]
}


resource "google_service_account" "runsa" {
  project      = var.project_id
  account_id   = "${var.deployment_name}-run-sa"
  display_name = "Service Account for Cloud Run"
}



resource "google_project_iam_member" "allrun" {
  project    = data.google_project.project.number
  role       = "roles/secretmanager.secretAccessor"
  member     = "serviceAccount:${google_service_account.runsa.email}"
  depends_on = [module.project-services]
}



module "network-safer-mysql-simple" {
  source  = "terraform-google-modules/network/google"
  version = "~> 4.0"

  project_id   = var.project_id
  network_name = "${var.deployment_name}-network"

  subnets = []
}

# resource "google_compute_network" "main" {
#   provider                = google-beta
#   name                    = "${var.deployment_name}-network"
#   auto_create_subnetworks = false
#   project                 = var.project_id
#   depends_on = [
#     module.project-services
#   ]
# }


module "private-service-access" {
  source      = "GoogleCloudPlatform/sql-db/google//modules/private_service_access"
  project_id  = var.project_id
  vpc_network = module.network-safer-mysql-simple.network_name
}


# # Handle Networking details
# resource "google_compute_global_address" "main" {
#   name          = "${var.deployment_name}-vpc-address"
#   provider      = google-beta
#   labels        = var.labels
#   purpose       = "VPC_PEERING"
#   address_type  = "INTERNAL"
#   prefix_length = 16
#   network       = google_compute_network.main.id
#   project       = var.project_id
#   depends_on    = [module.project-services]
# }

# resource "google_service_networking_connection" "main" {
#   network                 = google_compute_network.main.id
#   service                 = "servicenetworking.googleapis.com"
#   reserved_peering_ranges = [google_compute_global_address.main.name]
#   depends_on              = [module.project-services]
# }

resource "google_vpc_access_connector" "main" {
  provider       = google-beta
  project        = var.project_id
  name           = "${var.deployment_name}-vpc-cx"
  ip_cidr_range  = "10.8.0.0/28"
  network        = module.network-safer-mysql-simple.network_name
  region         = var.region
  max_throughput = 300
  depends_on     = [google_compute_global_address.main, module.project-services]
}

resource "random_id" "id" {
  byte_length = 2
}



module "mysql" {
  source               = "GoogleCloudPlatform/sql-db/google//modules/mysql"
  name                 = "${var.deployment_name}-db-${random_id.id.hex}"
  random_instance_name = false
  database_version     = "MYSQL_5_7"
  project_id           = var.project_id
  region               = var.region
  zone                 = var.zone
  deletion_protection  = false
  tier                 = "db-g1-small"
  user_labels          = var.labels

  ip_configuration = {
    ipv4_enabled    = false
    private_network = module.network-safer-mysql-simple.network_self_link
    # require_ssl         = true
    # allocated_ip_range  = null
    # authorized_networks = []
  }
}

# module "safer-mysql-db" {
#   source               = "GoogleCloudPlatform/sql-db/google//modules/safer_mysql"
#   name                 = "${var.deployment_name}-db-${random_id.id.hex}"
#   random_instance_name = false
#   project_id           = var.project_id

#   deletion_protection = false

#   database_version = "MYSQL_5_7"
#   region           = var.region
#   zone             = var.zone
#   tier                  = "db-g1-small"

#   // By default, all users will be permitted to connect only via the
#   // Cloud SQL proxy.
#   additional_users = [
#     {
#       name     = "app"
#       password = "PaSsWoRd"
#       host     = "localhost"
#       type     = "BUILT_IN"
#     },
#     {
#       name     = "readonly"
#       password = "PaSsWoRd"
#       host     = "localhost"
#       type     = "BUILT_IN"
#     },
#   ]

#   assign_public_ip   = "true"
#   vpc_network        = module.network-safer-mysql-simple.network_self_link
#   allocated_ip_range = module.private-service-access.google_compute_global_address_name

#   // Optional: used to enforce ordering in the creation of resources.
#   module_depends_on = [module.private-service-access.peering_completed]
# }

# Handle Database
# resource "google_sql_database_instance" "main" {
#   name             = "${var.deployment_name}-db-${random_id.id.hex}-2"
#   database_version = "MYSQL_5_7"
#   region           = var.region
#   project          = var.project_id

#   settings {
#     tier                  = "db-g1-small"
#     disk_autoresize       = true
#     disk_autoresize_limit = 0
#     disk_size             = 10
#     disk_type             = "PD_SSD"
#     user_labels           = var.labels
#     ip_configuration {
#       ipv4_enabled    = false
#       private_network = module.network-safer-mysql-simple.network_name
#     }
#     location_preference {
#       zone = var.zone
#     }
#   }
#   deletion_protection = false
#   depends_on = [
#     module.project-services,
#     google_vpc_access_connector.main,
#     google_service_networking_connection.main
#   ]


# }

resource "google_sql_database" "database" {
  project  = var.project_id
  name     = "todo"
  instance = module.mysql.instance_name
}



resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "google_sql_user" "main" {
  project  = var.project_id
  name     = "todo_user"
  password = random_password.password.result
  instance = google_sql_database_instance.main.name
}

# Looked at using the module, but there doesn't seem to be a huge win there.
# Handle redis instance
resource "google_redis_instance" "main" {
  authorized_network      = module.network-safer-mysql-simple.network_name
  connect_mode            = "DIRECT_PEERING"
  location_id             = var.zone
  memory_size_gb          = 1
  name                    = "${var.deployment_name}-cache"
  project                 = var.project_id
  redis_version           = "REDIS_6_X"
  region                  = var.region
  reserved_ip_range       = "10.137.125.88/29"
  tier                    = "BASIC"
  transit_encryption_mode = "DISABLED"
  depends_on              = [module.project-services]
  labels                  = var.labels
}



module "secret-manager" {
  source     = "GoogleCloudPlatform/secret-manager/google"
  version    = "~> 0.1"
  project_id = var.project_id
  secrets = [
    {
      name                  = "redishost"
      automatic_replication = true
      secret_data           = google_redis_instance.main.host
    },
    {
      name                  = "sqlhost"
      automatic_replication = true
      secret_data           = google_sql_database_instance.main.private_ip_address
    },
    {
      name                  = "todo_user"
      automatic_replication = true
      secret_data           = "todo_user"
    },
    {
      name                  = "todo_pass"
      automatic_replication = true
      secret_data           = data.google_project.project.number
    },
  ]
}


# Handle secrets
# resource "google_secret_manager_secret" "redishost" {
#   project = data.google_project.project.number
#   labels  = var.labels
#   replication {
#     automatic = true
#   }
#   secret_id  = "redishost"
#   depends_on = [module.project-services]
# }

# resource "google_secret_manager_secret_version" "redishost" {
#   enabled     = true
#   secret      = google_secret_manager_secret.redishost.id
#   secret_data = google_redis_instance.main.host
# }

# resource "google_secret_manager_secret" "sqlhost" {
#   project = data.google_project.project.number
#   labels  = var.labels
#   replication {
#     automatic = true
#   }
#   secret_id  = "sqlhost"
#   depends_on = [module.project-services]
# }

# resource "google_secret_manager_secret_version" "sqlhost" {
#   enabled     = true
#   secret      = google_secret_manager_secret.sqlhost.id
#   secret_data = google_sql_database_instance.main.private_ip_address
# }

# resource "google_secret_manager_secret" "todo_user" {
#   labels  = var.labels
#   project = data.google_project.project.number
#   replication {
#     automatic = true
#   }
#   secret_id  = "todo_user"
#   depends_on = [module.project-services]
# }
# resource "google_secret_manager_secret_version" "todo_user" {
#   enabled     = true
#   secret      = google_secret_manager_secret.todo_user.id
#   secret_data = "todo_user"
# }

# resource "google_secret_manager_secret" "todo_pass" {
#   labels  = var.labels
#   project = data.google_project.project.number
#   replication {
#     automatic = true
#   }
#   secret_id  = "todo_pass"
#   depends_on = [module.project-services]
# }
# resource "google_secret_manager_secret_version" "todo_pass" {
#   enabled     = true
#   secret      = google_secret_manager_secret.todo_pass.id
#   secret_data = google_sql_user.main.password
# }


resource "google_cloud_run_service" "api" {
  name     = "${var.deployment_name}-api"
  provider = google-beta
  location = var.region
  project  = var.project_id


  template {
    spec {
      service_account_name = google_service_account.runsa.email
      containers {
        image = local.api_image
        env {
          name = "REDISHOST"
          value_from {
            secret_key_ref {
              name = module.secret-manager.secret_names["redishost"]
              key  = "latest"
            }
          }
        }
        env {
          name = "todo_host"
          value_from {
            secret_key_ref {
              name = module.secret-manager.secret_names["sqlhost"]
              key  = "latest"
            }
          }
        }

        env {
          name = "todo_user"
          value_from {
            secret_key_ref {
              name = module.secret-manager.secret_names["todo_user"]
              key  = "latest"
            }
          }
        }

        env {
          name = "todo_pass"
          value_from {
            secret_key_ref {
              name = module.secret-manager.secret_names["todo_pass"]
              key  = "latest"
            }
          }
        }
        env {
          name  = "todo_name"
          value = "todo"
        }

        env {
          name  = "REDISPORT"
          value = "6379"
        }

      }
    }

    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale"        = "1000"
        "run.googleapis.com/cloudsql-instances"   = google_sql_database_instance.main.connection_name
        "run.googleapis.com/client-name"          = "terraform"
        "run.googleapis.com/vpc-access-egress"    = "all"
        "run.googleapis.com/vpc-access-connector" = google_vpc_access_connector.main.id

      }
    }
  }
  metadata {
    labels = var.labels
  }
  autogenerate_revision_name = true
  # I know, implicit dependencies. But I got flaky tests cause stuff didn't
  # exist yet. So explicit dependencies is what you get.
  depends_on = [
    google_project_iam_member.allrun,
    module.secret-manager
  ]
}


resource "google_cloud_run_service" "fe" {
  name     = "${var.deployment_name}-fe"
  location = var.region
  project  = var.project_id

  template {
    spec {
      service_account_name = google_service_account.runsa.email
      containers {
        image = local.fe_image
        ports {
          container_port = 80
        }
        env {
          name  = "ENDPOINT"
          value = google_cloud_run_service.api.status[0].url
        }
      }
    }
  }
  metadata {
    labels = var.labels
  }
}


resource "google_cloud_run_service_iam_member" "noauth_api" {
  location = google_cloud_run_service.api.location
  project  = google_cloud_run_service.api.project
  service  = google_cloud_run_service.api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_service_iam_member" "noauth_fe" {
  location = google_cloud_run_service.fe.location
  project  = google_cloud_run_service.fe.project
  service  = google_cloud_run_service.fe.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

