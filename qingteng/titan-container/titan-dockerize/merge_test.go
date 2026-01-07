package main

import (
	"strings"
	"testing"
)

func TestIndex(t *testing.T) {
	trimStr := "base.pbe=10203992=12121"
	index := strings.Index(trimStr, "=")
	println(index)
	key := trimStr[:index]
	valueStr := trimStr[index+1:]

	println(key)
	println(valueStr)
}
