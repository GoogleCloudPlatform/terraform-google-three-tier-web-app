// Copyright 2023 Google LLC
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
	"testing"
	"time"

	"github.com/GoogleCloudPlatform/cloud-foundation-toolkit/infra/blueprint-test/pkg/tft"
)

func TestMultipleDeploy(t *testing.T) {
	multipleDeployExample := tft.NewTFBlueprintTest(t, tft.WithRetryableTerraformErrors(retryErrors, 10, time.Minute))
	// RedeployTest will first perform the init, apply, verify stages
	// in two different TF workspaces and then teardown.
	// No custom verification performed here as that is handled in simple example.
	multipleDeployExample.RedeployTest(2, map[int]map[string]interface{}{
		1: {"deployment_name": "deployment-1"},
		2: {"deployment_name": "deployment-2"},
	})
}
