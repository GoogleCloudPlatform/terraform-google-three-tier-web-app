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

package simple_example

import (
	"fmt"
	"testing"
	"time"

	"github.com/GoogleCloudPlatform/cloud-foundation-toolkit/infra/blueprint-test/pkg/gcloud"
	"github.com/GoogleCloudPlatform/cloud-foundation-toolkit/infra/blueprint-test/pkg/tft"
	"github.com/GoogleCloudPlatform/cloud-foundation-toolkit/infra/blueprint-test/pkg/utils"
	test "github.com/GoogleCloudPlatform/terraform-google-three-tier-web-app/test/integration"
	"github.com/stretchr/testify/assert"
)

// Retry if these errors are encountered.
var retryErrors = map[string]string{
	// Error for Postgres SQL not deleting databases.
	".*is being accessed by other users.*": "Database will eventually let you delete it",
	".*SERVICE_DISABLED.*":                 "Service enablement is eventually consistent",
}

func TestSimpleExample(t *testing.T) {
	example := tft.NewTFBlueprintTest(t, tft.WithRetryableTerraformErrors(retryErrors, 10, time.Minute))

	example.DefineVerify(func(assert *assert.Assertions) {
		// DefaultVerify asserts no resource changes exist after apply.
		// It helps ensure that a second "terraform apply" wouldn't result in resource deletions/replacements.
		example.DefaultVerify(assert)

		sqlname := example.GetStringOutput("sqlservername")
		projectID := example.GetTFSetupStringOutput("project_id")
		prefix := "three-tier-app"
		region := "us-central1"

		labelTests := map[string]struct {
			subsection string
			name       string
			global     bool
			region     bool
			query      string
		}{
			"Label: Service api": {subsection: "run services", global: false, region: true, name: "three-tier-app-api", query: "metadata.labels.three-tier-app"},
			"Label: Service fe":  {subsection: "run services", global: false, region: true, name: "three-tier-app-fe", query: "metadata.labels.three-tier-app"},
			"Label: SQL":         {subsection: "sql instances", global: false, region: false, name: sqlname, query: "settings.userLabels.three-tier-app"},
			"Label: Redis":       {subsection: "redis instances", global: false, region: true, name: "three-tier-app-cache", query: "labels.three-tier-app"},
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
			"Existence: Service todo-fe":  {subsection: "run services", field: "metadata.name", global: false, region: true, expected: fmt.Sprintf("%s-fe", prefix)},
			"Existence: Service todo-api": {subsection: "run services", field: "metadata.name", global: false, region: true, expected: fmt.Sprintf("%s-api", prefix)},
			"Existence: Redis":            {subsection: "redis instances", field: "name", global: false, region: true, expected: fmt.Sprintf("projects/%s/locations/%s/instances/%s-cache", projectID, region, prefix)},
			"Existence: SQL":              {subsection: "sql instances", field: "name", global: false, region: false, expected: sqlname},
			"Existence: VPN Connector":    {subsection: "compute networks vpc-access connectors", field: "name", global: false, region: true, expected: fmt.Sprintf("projects/%s/locations/%s/connectors/%s-vpc-cx", projectID, region, prefix)},
			"Existence: PSC Address":      {subsection: "compute addresses", field: "name", global: false, region: true, expected: fmt.Sprintf("%s-sql-psc", prefix)},
			"Existence: Network":          {subsection: "compute networks", field: "name", global: false, region: false, expected: fmt.Sprintf("%s-private-network", prefix)},
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
			"Service compute":       {service: "compute"},
			"Service cloudapis":     {service: "cloudapis"},
			"Service vpcaccess":     {service: "vpcaccess"},
			"Service cloudbuild":    {service: "cloudbuild"},
			"Service sql-component": {service: "sql-component"},
			"Service sqladmin":      {service: "sqladmin"},
			"Service storage":       {service: "storage"},
			"Service secretmanager": {service: "secretmanager"},
			"Service run":           {service: "run"},
			"Service redis":         {service: "redis"},
		}

		services := gcloud.Run(t, "services list", gcloud.WithCommonArgs([]string{"--project", projectID, "--format", "json"})).Array()

		for name, tc := range serviceTests {
			t.Run(name, func(t *testing.T) {
				match := utils.GetFirstMatchResult(t, services, "config.name", fmt.Sprintf("%s.googleapis.com", tc.service))
				assert.Equal("ENABLED", match.Get("state").String(), "%s service should be enabled", tc.service)
			})
		}

		t.Run("API ingress and IAM restricted", func(t *testing.T) {
			ops := gcloud.WithCommonArgs([]string{"--project", projectID, "--format", "json", "--region", region})
			svc := gcloud.Run(t, fmt.Sprintf("run services describe %s-api", prefix), ops).Array()
			annotations := svc[0].Get("metadata.annotations").Map()
			assert.Equal("internal-and-cloud-load-balancing", annotations["run.googleapis.com/ingress"].String(), "expected API ingress to be restricted")

			policy := gcloud.Run(t, fmt.Sprintf("run services get-iam-policy %s-api", prefix), ops).Array()
			invokerSA := fmt.Sprintf("serviceAccount:%s-run-sa@%s.iam.gserviceaccount.com", prefix, projectID)
			foundInvoker := false
			for _, binding := range policy[0].Get("bindings").Array() {
				if binding.Get("role").String() == "roles/run.invoker" {
					for _, member := range binding.Get("members").Array() {
						assert.NotEqual("allUsers", member.String(), "API service must not allow allUsers")
						if member.String() == invokerSA {
							foundInvoker = true
						}
					}
				}
			}
			assert.True(foundInvoker, "expected runtime service account to have roles/run.invoker on API service")
		})

		deploymentUrl := example.GetStringOutput("endpoint")
		test.TestDeploymentUrl(t, deploymentUrl)
	})
	example.Test()
}
