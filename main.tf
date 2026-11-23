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
  api_image = (var.database_type == "mysql" ? "gcr.io/sic-container-repo/todo-api" : "gcr.io/sic-container-repo/todo-api-postgres:latest")
  fe_image  = "gcr.io/sic-container-repo/todo-fe"

  api_env_vars_postgresql = {
    redis_host = google_redis_instance.main.host
    db_host    = google_compute_address.sql_psc.address
    db_user    = google_service_account.runsa.email
    db_conn    = google_sql_database_instance.main.connection_name
    db_name    = "todo"
    redis_port = "6379"
  }

  mysql_username = "todo_user"

  api_env_vars_mysql = {
    REDISHOST = google_redis_instance.main.host
    todo_host = google_compute_address.sql_psc.address
    todo_user = local.mysql_username
    todo_name = "todo"
    REDISPORT = "6379"
  }
}

module "project-services" {
  source                      = "terraform-google-modules/project-factory/google//modules/project_services"
  version                     = "18.0.0"
  disable_services_on_destroy = false

  project_id  = var.project_id
  enable_apis = var.enable_apis

  activate_apis = [
    "compute.googleapis.com",
    "cloudapis.googleapis.com",
    "vpcaccess.googleapis.com",
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
  for_each = toset(var.run_roles_list)
  project  = data.google_project.project.number
  role     = each.key
  member   = "serviceAccount:${google_service_account.runsa.email}"
}

resource "google_compute_network" "main" {
  provider                = google-beta
  name                    = "${var.deployment_name}-private-network"
  auto_create_subnetworks = true
  project                 = var.project_id
}

data "google_compute_subnetwork" "main" {
  name       = google_compute_network.main.name
  region     = var.region
  project    = var.project_id
  depends_on = [google_compute_network.main]
}

# PSC = Private Service Connect
resource "google_compute_address" "sql_psc" {
  name         = "${var.deployment_name}-sql-psc"
  project      = var.project_id
  region       = var.region
  address_type = "INTERNAL"
  subnetwork   = data.google_compute_subnetwork.main.id
}

resource "google_compute_forwarding_rule" "sql_psc" {
  name                  = "${var.deployment_name}-sql-psc"
  project               = var.project_id
  region                = var.region
  network               = google_compute_network.main.id
  ip_address            = google_compute_address.sql_psc.id
  load_balancing_scheme = ""
  target                = google_sql_database_instance.main.psc_service_attachment_link
}

resource "google_vpc_access_connector" "main" {
  provider       = google-beta
  project        = var.project_id
  name           = "${var.deployment_name}-vpc-cx"
  ip_cidr_range  = "10.8.0.0/28"
  network        = google_compute_network.main.name
  region         = var.region
  max_throughput = 300
  min_throughput = 200
  depends_on     = [time_sleep.wait_before_destroying_network]
}

# The google_vpc_access_connector resource creates some firewalls that sometimes takes a while to destroy
# and causes errors when we try to destroy the VPC network (google_compute_network).
resource "time_sleep" "wait_before_destroying_network" {
  depends_on       = [google_compute_network.main]
  destroy_duration = "60s"
}

# Looked at using the module, but there doesn't seem to be a huge win there.
# Handle redis instance
resource "google_redis_instance" "main" {
  authorized_network      = google_compute_network.main.name
  connect_mode            = "DIRECT_PEERING"
  location_id             = var.zone
  memory_size_gb          = 1
  name                    = "${var.deployment_name}-cache"
  display_name            = "${var.deployment_name}-cache"
  project                 = var.project_id
  redis_version           = "REDIS_6_X"
  region                  = var.region
  reserved_ip_range       = "10.137.125.88/29"
  tier                    = "BASIC"
  transit_encryption_mode = "DISABLED"
  labels                  = var.labels
}

resource "random_id" "id" {
  byte_length = 2
}

# Handle Database
resource "google_sql_database_instance" "main" {
  name             = "${var.deployment_name}-db-${random_id.id.hex}"
  database_version = (var.database_type == "mysql" ? "MYSQL_8_0" : "POSTGRES_14")
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
      ipv4_enabled = false
      # PSC = Private Service Connect
      psc_config {
        psc_enabled               = true
        allowed_consumer_projects = [var.project_id]
      }
    }
    location_preference {
      zone = var.zone
    }
    dynamic "database_flags" {
      for_each = var.database_type == "postgresql" ? [1] : []
      content {
        name  = "cloudsql.iam_authentication"
        value = "on"
      }
    }
  }
  deletion_protection = false
}


resource "random_password" "mysql_password" {
  count   = var.database_type == "mysql" ? 1 : 0
  length  = 24
  special = false
}

resource "google_secret_manager_secret" "mysql_password" {
  count     = var.database_type == "mysql" ? 1 : 0
  project   = var.project_id
  secret_id = "${var.deployment_name}-mysql-password-${random_id.id.hex}"
  labels    = var.labels

  replication {
    auto {}
  }

  depends_on = [module.project-services]
}

resource "google_secret_manager_secret_version" "mysql_password" {
  count       = var.database_type == "mysql" ? 1 : 0
  secret      = google_secret_manager_secret.mysql_password[0].id
  secret_data = random_password.mysql_password[0].result
}

resource "google_secret_manager_secret_iam_member" "mysql_password_accessor" {
  count     = var.database_type == "mysql" ? 1 : 0
  project   = var.project_id
  secret_id = google_secret_manager_secret.mysql_password[0].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runsa.email}"
}

resource "google_sql_user" "main" {
  project         = var.project_id
  instance        = google_sql_database_instance.main.name
  deletion_policy = "ABANDON"
  name            = var.database_type == "postgresql" ? "${google_service_account.runsa.account_id}@${var.project_id}.iam" : local.mysql_username
  type            = var.database_type == "postgresql" ? "CLOUD_IAM_SERVICE_ACCOUNT" : null
  password        = one(random_password.mysql_password[*].result)
}

resource "google_sql_database" "database" {
  project         = var.project_id
  name            = "todo"
  instance        = google_sql_database_instance.main.name
  deletion_policy = "ABANDON"
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
        dynamic "env" {
          for_each = var.database_type == "postgresql" ? local.api_env_vars_postgresql : local.api_env_vars_mysql
          content {
            name  = env.key
            value = env.value
          }
        }
        dynamic "env" {
          for_each = var.database_type == "mysql" ? [1] : []
          content {
            name = "todo_pass"
            value_from {
              secret_key_ref {
                name = google_secret_manager_secret.mysql_password[0].secret_id
                key  = "latest"
              }
            }
          }
        }
      }
    }

    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale"        = "8"
        "run.googleapis.com/cloudsql-instances"   = google_sql_database_instance.main.connection_name
        "run.googleapis.com/client-name"          = "terraform"
        "run.googleapis.com/vpc-access-egress"    = "all"
        "run.googleapis.com/vpc-access-connector" = google_vpc_access_connector.main.id
      }
      labels = {
        "run.googleapis.com/startupProbeType" = "Default"
      }
    }
  }
  metadata {
    annotations = {
      "run.googleapis.com/ingress" = "internal-and-cloud-load-balancing"
    }
    labels = var.labels
  }
  autogenerate_revision_name = true
  depends_on = [
    google_sql_user.main,
    google_sql_database.database,
    google_secret_manager_secret_version.mysql_password,
    google_secret_manager_secret_iam_member.mysql_password_accessor,
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
    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale" = "8"
      }
      labels = {
        "run.googleapis.com/startupProbeType" = "Default"
      }
    }
  }
  metadata {
    labels = var.labels
  }
}

resource "google_cloud_run_service_iam_member" "api_invoker" {
  location = google_cloud_run_service.api.location
  project  = google_cloud_run_service.api.project
  service  = google_cloud_run_service.api.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.runsa.email}"
}

resource "google_cloud_run_service_iam_member" "noauth_fe" {
  location = google_cloud_run_service.fe.location
  project  = google_cloud_run_service.fe.project
  service  = google_cloud_run_service.fe.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
