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

output "endpoint" {
  value       = google_cloud_run_service.fe.status[0].url
  description = "The url of the front end which we want to surface to the user"
}
output "sqlservername" {
  value       = google_sql_database_instance.main.name
  description = "The name of the database that we randomly generated."
}

output "neos_toc_url" {
  value       = "https://console.cloud.google.com/products/solutions/deployments?walkthrough_id=panels--sic--three-tier-web-app&project=${var.project_id}"
  description = "The URL to launch the in-console tutorial for the Three Tier App solution"
}
