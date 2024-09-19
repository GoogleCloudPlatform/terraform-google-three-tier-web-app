package integration

import (
	"fmt"
	"io/ioutil"
	"net/http"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestDeploymentUrl(t *testing.T, assert *assert.Assertions, url string) error {
	for attemptNum := 1; attemptNum <= 60; attemptNum++ {

		response, err := http.Get(url)
		if err != nil {
			t.Logf("Deployment URL HTTP request error: %s\n", err)

		} else if 200 <= response.StatusCode && response.StatusCode <= 299 { // Got some 200 response
			responseBody, err := ioutil.ReadAll(response.Body)
			if err != nil {
				return err
			}
			responseBodyString := string(responseBody)
			assert.Containsf(responseBodyString, "<title>Todo</title>", "Couldn't find text '<title>Todo</title>' in deployment's response")
			return nil

		} else { // Got a non-200 response
			t.Logf("Deployment URL responded with status code: %d.\n", response.StatusCode)
		}

		// Wait before retrying
		time.Sleep(4 * time.Second)
	}

	return fmt.Errorf("Deployment URL %s failed to respond with a 200 status code even after a few minutes.", url)
}
