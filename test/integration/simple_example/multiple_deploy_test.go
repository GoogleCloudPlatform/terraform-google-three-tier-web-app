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
