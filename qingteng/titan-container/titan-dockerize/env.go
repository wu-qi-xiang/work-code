package main

import (
	"encoding/json"
	"io/ioutil"
	"os"
	"strings"

	"sigs.k8s.io/yaml"
)

func setDefaultEnv(defaultEnv map[string]string) {
	for k, v := range defaultEnv {
		if _, ok := os.LookupEnv(k); !ok {
			if err := os.Setenv(k, v); err != nil {
				fatalf("Failed to set environment: %s.", err)
			}
		}
	}
}

func getEnv() map[string]string {
	env := make(map[string]string)
	for _, kv := range os.Environ() {
		parts := strings.SplitN(kv, "=", 2)
		env[parts[0]] = parts[1]
	}
	return env
}

func loadEnvFromYaml(env map[string]string, yamlPath string) map[string]string {
	yamlFile, err := ioutil.ReadFile(yamlPath)
	if err != nil {
		panic(err)
	}
	var yamlEnv map[string]interface{}
	err = yaml.Unmarshal(yamlFile, &yamlEnv)
	if err != nil {
		panic(err)
	}

	for key, value := range yamlEnv {
		if value == nil {
			env[key] = ""
			continue
		}
		valueBytes, err := json.Marshal(value)
		if err != nil {
			panic(err)
		}
		env[key] = strings.Trim(string(valueBytes), `"`)
	}

	return env
}
