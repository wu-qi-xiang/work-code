package main

import (
	"encoding/json"
	"io/ioutil"
	"os"
	"strconv"
	"strings"
)

func processMergeToJson(cfg templateConfig, mergeToJsonPaths []string) {
	for _, mergePathStr := range mergeToJsonPaths {
		tmpStrs := strings.Split(mergePathStr, ":")
		propPath := tmpStrs[0]
		jsonPath := tmpStrs[1]

		newJsonPath := jsonPath
		if len(tmpStrs) == 3 {
			newJsonPath = tmpStrs[2]
		}

		mergePropertiesToJson(cfg, propPath, jsonPath, newJsonPath)
	}

}

// props example:  base.pbeconfig : n8NK3aDid89UwBepSxWJPEHzfn0RH1wh
func mergePropertiesToJson(cfg templateConfig, propPath string, jsonPath string, newJsonPath string) {
	props := getProperties(cfg, propPath)

	jsonFileBytes, err := ioutil.ReadFile(jsonPath)
	if err != nil {
		panic(err)
	}
	jsonMap := make(map[string]interface{})
	err = json.Unmarshal(jsonFileBytes, &jsonMap)
	if err != nil {
		panic(err)
	}

	for key, value := range props {
		updateByKeyPath(jsonMap, key, value)
	}

	newJsonBytes, err := json.MarshalIndent(&jsonMap, "", "    ")
	if err != nil {
		panic(err)
	}

	err = ioutil.WriteFile(newJsonPath, newJsonBytes, os.ModePerm)
	if err != nil {
		panic(err)
	}
}

func updateByKeyPath(jsonMap map[string]interface{}, keyPath string, value interface{}) {
	strs := strings.Split(keyPath, ".")
	last := strs[len(strs)-1]
	paths := strs[:len(strs)-1]
	scope := jsonMap
	for _, path := range paths {
		if scope[path] == nil {
			newscope := make(map[string]interface{})
			scope[path] = newscope
			scope = newscope
		} else {
			if value, ok := scope[path].(map[string]interface{}); ok {
				scope = value
			} else {
				panic("error while update :" + keyPath)
			}
		}
	}

	scope[last] = value
}

func processMergeToIni(cfg templateConfig, mergeToIniPaths []string) {
	for _, mergePathStr := range mergeToIniPaths {
		tmpStrs := strings.Split(mergePathStr, ":")
		propPath := tmpStrs[0]
		iniPath := tmpStrs[1]

		newIniPath := iniPath
		if len(tmpStrs) == 3 {
			newIniPath = tmpStrs[2]
		}

		mergePropertiesToIni(cfg, propPath, iniPath, newIniPath)
	}

}

// 从 properties 文件模板 合并到 ini 文件
func mergePropertiesToIni(cfg templateConfig, propPath string, iniPath string, newIniPath string) {
	// 先处理 properties 模板，替换其中的变量
	propertiesContent, err := processPropertiesTemplate(cfg, propPath)
	if err != nil {
		panic(err)
	}
	// println(propertiesContent)

	ini, err := ioutil.ReadFile(iniPath)
	if err != nil {
		panic(err)
	}

	properties := make(map[string]string)
	for _, line := range strings.Split(propertiesContent, "\n") {
		trimStr := strings.TrimSpace(line)
		if trimStr == "" || strings.HasPrefix(trimStr, "#") {
			continue
		}

		if !strings.Contains(trimStr, "=") {
			continue
		}

		index := strings.Index(trimStr, "=")
		key := trimStr[:index]
		valueStr := trimStr[index+1:]
		properties[key] = valueStr
	}

	iniLines := strings.Split(string(ini), "\n")
	for index, line := range iniLines {
		lineStr := strings.TrimSpace(line)
		if lineStr == "" || strings.HasPrefix(lineStr, "#") {
			continue
		}
		if !strings.Contains(lineStr, "=") {
			continue
		}
		tmpStrs := strings.Split(lineStr, "=")
		key := tmpStrs[0]

		if value, ok := properties[key]; ok {
			iniLines[index] = key + "=" + value
		}

	}

	newIni := strings.Join(iniLines, "\n")

	err = ioutil.WriteFile(newIniPath, []byte(newIni), os.ModePerm)
	if err != nil {
		panic(err)
	}
}

// 从 properties文件加载到 Map
func getProperties(cfg templateConfig, propertiesFile string) map[string]interface{} {
	result := make(map[string]interface{})

	// 先处理 properties 模板，替换其中的变量
	propertiesContent, err := processPropertiesTemplate(cfg, propertiesFile)
	if err != nil {
		panic(err)
	}
	// println(propertiesContent)

	lines := strings.Split(propertiesContent, "\n")
	for _, line := range lines {
		trimStr := strings.TrimSpace(line)
		if trimStr == "" {
			continue
		}

		if strings.HasPrefix(trimStr, "#") {
			continue
		}

		index := strings.Index(trimStr, "=")
		key := trimStr[:index]
		valueStr := trimStr[index+1:]

		if valueStr == "false" {
			result[key] = false
		} else if valueStr == "true" {
			result[key] = true
		} else if floatValue, err := strconv.ParseFloat(valueStr, 64); err == nil {
			result[key] = floatValue
		} else if intValue, err := strconv.Atoi(valueStr); err == nil {
			result[key] = intValue
		} else {
			// string
			result[key] = strings.Trim(valueStr, "\"")
		}

	}

	return result
}
