package main

import (
	"fmt"
	"testing"
)

func TestPbe(t *testing.T) {
	enc, err := encryptPbe("O1Sdi171Cr4oE11RtNHYuaSqoN56fk2j", "FnQ3Z3CKz8LYVl2P")
	if err != nil {
		panic(err)
	}

	fmt.Println(enc)

	plain, err := decryptPbe("O1Sdi171Cr4oE11RtNHYuaSqoN56fk2j", "ENC(04rxPcEpJaOVpbV/Lz9gddirz7k377M42kn92c787PM=)")
	if err != nil {
		panic(err)
	}

	fmt.Println(plain)
}
