// Copyright 2022 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package multiple_buckets

import (
	"fmt"
	"testing"

	"github.com/GoogleCloudPlatform/cloud-foundation-toolkit/infra/blueprint-test/pkg/gcloud"
	"github.com/GoogleCloudPlatform/cloud-foundation-toolkit/infra/blueprint-test/pkg/tft"
	"github.com/GoogleCloudPlatform/cloud-foundation-toolkit/infra/blueprint-test/pkg/utils"
	"github.com/stretchr/testify/assert"
)

func TestSimpleExample(t *testing.T) {
	example := tft.NewTFBlueprintTest(t)

	sqlname := example.GetStringOutput("sqlservername")
	projectID := example.GetTFSetupStringOutput("project_id")
	projectNumber := example.GetTFSetupStringOutput("project_number")
	prefix := "three-tier-app"
	region := "us-central1"

	example.DefineVerify(func(assert *assert.Assertions) {
		example.DefaultVerify(assert)

		labelTests := map[string]struct {
			subsection string
			name       string
			global     bool
			region     bool
			query      string
		}{
			"Label: Secret SQLHost":   {subsection: "secrets", global: false, region: false, name: "sqlhost", query: "labels.three-tier-app"},
			"Label: Secret RedisHost": {subsection: "secrets", global: false, region: false, name: "redishost", query: "labels.three-tier-app"},
			"Label: Secret todo_user": {subsection: "secrets", global: false, region: false, name: "todo_user", query: "labels.three-tier-app"},
			"Label: Secret todo_pass": {subsection: "secrets", global: false, region: false, name: "todo_pass", query: "labels.three-tier-app"},
			"Label: Service api":      {subsection: "run services", global: false, region: true, name: "three-tier-app-api", query: "metadata.labels.three-tier-app"},
			"Label: Service fe":       {subsection: "run services", global: false, region: true, name: "three-tier-app-fe", query: "metadata.labels.three-tier-app"},
			"Label: SQL":              {subsection: "sql instances", global: false, region: false, name: sqlname, query: "settings.userLabels.three-tier-app"},
			"Label: Redis":            {subsection: "redis instances", global: false, region: true, name: "three-tier-app-cache", query: "labels.three-tier-app"},
		}

		for name, tc := range labelTests {
			t.Run(name, func(t *testing.T) {
				gcloudOps := gcloud.WithCommonArgs([]string{"--project", projectID, "--format", "json"})
				if tc.region {
					gcloudOps = gcloud.WithCommonArgs([]string{"--project", projectID, "--format", "json", "--region", region})
				}

				cmdstr := fmt.Sprintf("%s describe %s", tc.subsection, tc.name)
				template := gcloud.Run(t, cmdstr, gcloudOps).Array()

				match := template[0].Get(tc.query).String()
				assert.Equal("true", match, fmt.Sprintf("expected label (three-tier-app) in subsection %s to be present", tc.subsection))
			})
		}

		existenceTests := map[string]struct {
			subsection string
			field      string
			global     bool
			region     bool
			expected   string
		}{
			"Existence: Secret SQLHost":   {subsection: "secrets", field: "name", global: false, region: false, expected: fmt.Sprintf("projects/%s/secrets/sqlhost", projectNumber)},
			"Existence: Secret RedisHost": {subsection: "secrets", field: "name", global: false, region: false, expected: fmt.Sprintf("projects/%s/secrets/redishost", projectNumber)},
			"Existence: Secret todo_user": {subsection: "secrets", field: "name", global: false, region: false, expected: fmt.Sprintf("projects/%s/secrets/todo_user", projectNumber)},
			"Existence: Secret todo_pass": {subsection: "secrets", field: "name", global: false, region: false, expected: fmt.Sprintf("projects/%s/secrets/todo_pass", projectNumber)},
			"Existence: Service todo-fe":  {subsection: "run services", field: "metadata.name", global: false, region: true, expected: fmt.Sprintf("%s-fe", prefix)},
			"Existence: Service todo-api": {subsection: "run services", field: "metadata.name", global: false, region: true, expected: fmt.Sprintf("%s-api", prefix)},
			"Existence: Redis":            {subsection: "redis instances", field: "name", global: false, region: true, expected: fmt.Sprintf("projects/%s/locations/%s/instances/%s-cache", projectID, region, prefix)},
			"Existence: SQL":              {subsection: "sql instances", field: "name", global: false, region: false, expected: sqlname},
			"Existence: VPN Connector":    {subsection: "compute networks vpc-access connectors", field: "name", global: false, region: true, expected: fmt.Sprintf("projects/%s/locations/%s/connectors/%s-vpc-cx", projectID, region, prefix)},
			"Existence: VPN Address":      {subsection: "compute addresses", field: "name", global: true, region: false, expected: fmt.Sprintf("%s-vpc-address", prefix)},
		}

		for name, tc := range existenceTests {
			t.Run(name, func(t *testing.T) {
				gcloudOps := gcloud.WithCommonArgs([]string{"--project", projectID, "--format", "json"})
				if tc.global {
					gcloudOps = gcloud.WithCommonArgs([]string{"--project", projectID, "--format", "json", "--global"})
				}
				if tc.region {
					gcloudOps = gcloud.WithCommonArgs([]string{"--project", projectID, "--format", "json", "--region", region})
				}

				cmdstr := fmt.Sprintf("%s describe %s", tc.subsection, tc.expected)
				template := gcloud.Run(t, cmdstr, gcloudOps).Array()

				got := utils.GetFirstMatchResult(t, template, tc.field, tc.expected).Get(tc.field).String()
				assert.Equal(tc.expected, got, fmt.Sprintf("expected %s got %s", tc.expected, got))
			})
		}

		serviceTests := map[string]struct {
			service string
		}{
			"Service compute":           {service: "compute"},
			"Service cloudapis":         {service: "cloudapis"},
			"Service vpcaccess":         {service: "vpcaccess"},
			"Service servicenetworking": {service: "servicenetworking"},
			"Service cloudbuild":        {service: "cloudbuild"},
			"Service sql-component":     {service: "sql-component"},
			"Service sqladmin":          {service: "sqladmin"},
			"Service storage":           {service: "storage"},
			"Service secretmanager":     {service: "secretmanager"},
			"Service run":               {service: "run"},
			"Service redis":             {service: "redis"},
		}

		services := gcloud.Run(t, "services list", gcloud.WithCommonArgs([]string{"--project", projectID, "--format", "json"})).Array()

		for name, tc := range serviceTests {
			t.Run(name, func(t *testing.T) {
				match := utils.GetFirstMatchResult(t, services, "config.name", fmt.Sprintf("%s.googleapis.com", tc.service))
				assert.Equal("ENABLED", match.Get("state").String(), "%s service should be enabled", tc.service)
			})
		}
	})
	example.Test()
}
