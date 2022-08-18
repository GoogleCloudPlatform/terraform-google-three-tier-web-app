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
  depends_on = [
    module.project-services
  ]
}

module "private-service-access" {
  source      = "GoogleCloudPlatform/sql-db/google//modules/private_service_access"
  project_id  = var.project_id
  vpc_network = module.network-safer-mysql-simple.network_name
  depends_on = [
    module.project-services
  ]
}

resource "google_vpc_access_connector" "main" {
  provider       = google-beta
  project        = var.project_id
  name           = "${var.deployment_name}-vpc-cx"
  ip_cidr_range  = "10.8.0.0/28"
  network        = module.network-safer-mysql-simple.network_name
  region         = var.region
  max_throughput = 300
  depends_on     = [module.project-services]
}

resource "random_id" "id" {
  byte_length = 2
}

# Handle Database
resource "google_sql_database_instance" "main" {
  name             = "${var.deployment_name}-db-${random_id.id.hex}"
  database_version = "MYSQL_5_7"
  region           = var.region
  project          = var.project_id

  settings {
    tier                  = "db-g1-small"
    disk_autoresize       = true
    disk_autoresize_limit = 0
    disk_size             = 10
    disk_type             = "PD_SSD"
    user_labels           = var.labels
    ip_configuration {
      ipv4_enabled    = false
      private_network = module.network-safer-mysql-simple.network_self_link
    }
    location_preference {
      zone = var.zone
    }
  }
  deletion_protection = false
  depends_on = [
    module.project-services,
    google_vpc_access_connector.main,
  ]
}

resource "google_sql_database" "database" {
  project  = var.project_id
  name     = "todo"
  instance = google_sql_database_instance.main.name
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
  labels = {
    redishost = var.labels,
    sqlhost   = var.labels,
    todo_user = var.labels,
    todo_pass = var.labels
  }
  secrets = [
    {
      name                  = "redishost"
      automatic_replication = true
      secret_data           = google_redis_instance.main.host
    },
    {
      name                  = "sqlhost"
      automatic_replication = true
      secret_data           = google_sql_database_instance.main.ip_address.0.ip_address
    },
    {
      name                  = "todo_user"
      automatic_replication = true
      secret_data           = "todo_user"
    },
    {
      name                  = "todo_pass"
      automatic_replication = true
      secret_data           = google_sql_user.main.password
    },
  ]
}

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
              name = "redishost"
              key  = "latest"
            }
          }
        }
        env {
          name = "todo_host"
          value_from {
            secret_key_ref {
              name = "sqlhost"
              key  = "latest"
            }
          }
        }

        env {
          name = "todo_user"
          value_from {
            secret_key_ref {
              name = "todo_user"
              key  = "latest"
            }
          }
        }

        env {
          name = "todo_pass"
          value_from {
            secret_key_ref {
              name = "todo_pass"
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

