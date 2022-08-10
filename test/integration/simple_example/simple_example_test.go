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
	"testing"

	"github.com/GoogleCloudPlatform/cloud-foundation-toolkit/infra/blueprint-test/pkg/gcloud"
	"github.com/GoogleCloudPlatform/cloud-foundation-toolkit/infra/blueprint-test/pkg/tft"
	"github.com/GoogleCloudPlatform/cloud-foundation-toolkit/infra/blueprint-test/pkg/utils"
	"github.com/stretchr/testify/assert"
)

func TestSimpleExample(t *testing.T) {
	example := tft.NewTFBlueprintTest(t)

	projectID := example.GetTFSetupStringOutput("project_id")
	// prefix := "three-tier-app"
	// region := "us-central1"
	// zone := "us-central1-a"

	example.DefineVerify(func(assert *assert.Assertions) {
		example.DefaultVerify(assert)

		// labelTests := map[string]struct {
		// 	subsection string
		// 	name       string
		// 	zone       bool
		// 	query      string
		// }{
		// 	"Label: Exemplar":          {subsection: "instances", name: fmt.Sprintf("%s-exemplar", prefix), zone: true, query: "labels.load-balanced-vms"},
		// 	"Label: Instance Template": {subsection: "instance-templates", name: fmt.Sprintf("%s-template", prefix), query: "properties.labels.load-balanced-vms"},
		// 	"Label: Image":             {subsection: "images", name: fmt.Sprintf("%s-latest", prefix), query: "labels.load-balanced-vms"},
		// 	"Label: Snapshot":          {subsection: "snapshots", name: fmt.Sprintf("%s-snapshot", prefix), query: "labels.load-balanced-vms"},
		// }

		// for name, tc := range labelTests {
		// 	t.Run(name, func(t *testing.T) {
		// 		gcloudOps := gcloud.WithCommonArgs([]string{"--project", projectID, "--format", "json"})
		// 		if tc.zone {
		// 			gcloudOps = gcloud.WithCommonArgs([]string{"--project", projectID, "--format", "json", "--zone", zone})
		// 		}

		// 		cmdstr := fmt.Sprintf("compute %s describe %s", tc.subsection, tc.name)
		// 		template := gcloud.Run(t, cmdstr, gcloudOps).Array()

		// 		match := template[0].Get(tc.query).String()
		// 		assert.Equal("true", match, fmt.Sprintf("expected label (loadbalanced-vms) in subsection %s to be present", tc.subsection))
		// 	})
		// }

		// existenceTests := map[string]struct {
		// 	subsection string
		// 	global     bool
		// 	zone       bool
		// 	expected   string
		// }{
		// 	"Existence: Snapshot":            {subsection: "snapshots", global: false, zone: false, expected: fmt.Sprintf("%s-snapshot", prefix)},
		// 	"Existence: Instance Group":      {subsection: "instance-groups managed", global: false, zone: true, expected: fmt.Sprintf("%s-mig", prefix)},
		// 	"Existence: Image":               {subsection: "images", global: false, expected: fmt.Sprintf("%s-latest", prefix)},
		// 	"Existence: Template":            {subsection: "instance-templates", global: false, expected: fmt.Sprintf("%s-template", prefix)},
		// 	"Existence: Forwarding Rules":    {subsection: "forwarding-rules", global: true, expected: fmt.Sprintf("%s-lb", prefix)},
		// 	"Existence: Target HTTP Proxies": {subsection: "target-http-proxies", global: true, expected: fmt.Sprintf("%s-lb-http-proxy", prefix)},
		// 	"Existence: URL Maps":            {subsection: "url-maps", global: true, expected: fmt.Sprintf("%s-lb-url-map", prefix)},
		// 	"Existence: Backend Services":    {subsection: "backend-services", global: true, expected: fmt.Sprintf("%s-lb-backend-default", prefix)},
		// 	"Existence: Address":             {subsection: "addresses", global: true, expected: fmt.Sprintf("%s-lb-address", prefix)},
		// }

		// for name, tc := range existenceTests {
		// 	t.Run(name, func(t *testing.T) {
		// 		gcloudOps := gcloud.WithCommonArgs([]string{"--project", projectID, "--format", "json"})
		// 		if tc.global {
		// 			gcloudOps = gcloud.WithCommonArgs([]string{"--project", projectID, "--format", "json", "--global"})
		// 		}
		// 		if tc.zone {
		// 			gcloudOps = gcloud.WithCommonArgs([]string{"--project", projectID, "--format", "json", "--zone", zone})
		// 		}

		// 		cmdstr := fmt.Sprintf("compute %s describe %s", tc.subsection, tc.expected)
		// 		template := gcloud.Run(t, cmdstr, gcloudOps).Array()

		// 		match := utils.GetFirstMatchResult(t, template, "name", tc.expected)
		// 		assert.Equal(tc.expected, match.Get("name").String(), fmt.Sprintf("expected %s", tc.expected))
		// 	})
		// }

		serviceTests := map[string]struct {
			service string
		}{
			"Service compute": {service: "compute.googleapis.com"},
			// "Label: Instance Template": {subsection: "instance-templates", name: fmt.Sprintf("%s-template", prefix), query: "properties.labels.load-balanced-vms"},
			// "Label: Image":             {subsection: "images", name: fmt.Sprintf("%s-latest", prefix), query: "labels.load-balanced-vms"},
			// "Label: Snapshot":          {subsection: "snapshots", name: fmt.Sprintf("%s-snapshot", prefix), query: "labels.load-balanced-vms"},
		}

		services := gcloud.Run(t, "services list", gcloud.WithCommonArgs([]string{"--project", projectID, "--format", "json"})).Array()

		for name, tc := range serviceTests {
			t.Run(name, func(t *testing.T) {
				match := utils.GetFirstMatchResult(t, services, "config.name", tc.service)
				assert.Equal("ENABLED", match.Get("state").String(), "%s service should be enabled", tc.service)
			})
		}

		// t.Run("Outputs Value", func(t *testing.T) {
		// 	got := example.GetStringOutput("console_page")
		// 	expected := fmt.Sprintf("/net-services/loadbalancing/details/http/%s-lb-url-map?project=%s", prefix, projectID)
		// 	assert.Equal(expected, got, "console page: expected (%s) got (%s)", expected, got)

		// 	ip := example.GetStringOutput("endpoint")
		// 	val := net.ParseIP(ip)
		// 	assert.NotNil(val, "endpoint: expected (%s) to be valid IP", ip)
		// })
	})
	example.Test()
}
