// Copyright 2024 Google LLC
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

package mysql

import (
	"testing"
	"time"

	"github.com/GoogleCloudPlatform/cloud-foundation-toolkit/infra/blueprint-test/pkg/tft"
	test "github.com/GoogleCloudPlatform/terraform-google-three-tier-web-app/test/integration"
	"github.com/stretchr/testify/assert"
)

// Retry if these errors are encountered.
var retryErrors = map[string]string{
	// Error for Cloud SQL not deleting databases.
	".*is being accessed by other users.*": "Database will eventually let you delete it",
	".*SERVICE_DISABLED.*":                 "Service enablement is eventually consistent",
}

func TestMysql(t *testing.T) {
	blueprintTest := tft.NewTFBlueprintTest(t, tft.WithRetryableTerraformErrors(retryErrors, 10, time.Minute))

	blueprintTest.DefineVerify(func(assert *assert.Assertions) {
		// DefaultVerify asserts no resource changes exist after apply.
		// It helps ensure that a second "terraform apply" wouldn't result in resource deletions/replacements.
		blueprintTest.DefaultVerify(assert)

		deploymentUrl := blueprintTest.GetStringOutput("endpoint")
		test.TestDeploymentUrl(t, deploymentUrl)
	})

	blueprintTest.Test()
}
