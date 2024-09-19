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

package test

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
