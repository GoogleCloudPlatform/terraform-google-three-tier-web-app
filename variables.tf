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

variable "project_id" {
  type        = string
  description = "The project ID to deploy to"
}

variable "region" {
  type        = string
  description = "The Compute Region to deploy to"
}

variable "zone" {
  type        = string
  description = "The Compute Zone to deploy to"
}

variable "deployment_name" {
  type        = string
  description = "The name of this particular deployment, will get added as a prefix to most resources."
  default     = "three-tier-app"
}

variable "labels" {
  type        = map(string)
  description = "A map of labels to apply to contained resources."
  default     = { "three-tier-app" = true }
}

variable "enable_apis" {
  type        = string
  description = "Whether or not to enable underlying apis in this solution. ."
  default     = true
}

variable "run_roles_list" {
  description = "The list of roles that run needs"
  type        = list(string)
  default = [
    "roles/cloudsql.instanceUser",
    "roles/cloudsql.client",
  ]
}
