package main

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"io/ioutil"
	"math/big"
	"os"
	"path/filepath"
	"strings"
)

const (
	LOWER_LETTERS = "abcdefghijklmnopqrstuvwxyz"
	UPPER_LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	NUMBERS       = "0123456789"
	// java代码里暂不支持mongo包含%
	SECRET_CHARS = LOWER_LETTERS + UPPER_LETTERS + NUMBERS + "_"
)

const iterationCount = 1103
const defaultSecretDir = "/run/secrets"

var servicePasswordFileMap = map[string]string{
	"mysql":     "mysql_password",
	"mongo":     "mongo_password",
	"zookeeper": "zk_password",
	"kafka":     "kafka_password",
	"redisjava": "redisjava_password",
	"redisphp":  "redisphp_password",
	"rediserl":  "rediserl_password",
	"rabbitmq":  "rabbitmq_password",
}

func randSecret(length int) string {
	var result string
	maxInt := big.NewInt(int64(len(SECRET_CHARS)))
	for i := 0; i < length; i++ {
		randomInt, _ := rand.Int(rand.Reader, maxInt)
		result += string(SECRET_CHARS[randomInt.Int64()])
	}
	return result
}

func createSecretFile(secretPath string) error {
	secret := randSecret(16)
	encSecret, err := encryptPbe(pbeconfig, secret)
	if err != nil {
		return err
	}

	return ioutil.WriteFile(secretPath, []byte(encSecret), os.ModePerm)
}

//使用PKCS7进行填充
func pKCS7Padding(plaintext []byte, blockSize int) []byte {
	padding := blockSize - len(plaintext)%blockSize
	padtext := bytes.Repeat([]byte{byte(padding)}, padding)
	return append(plaintext, padtext...)
}

func pKCS7UnPadding(plaintext []byte) []byte {
	length := len(plaintext)
	unpadding := int(plaintext[length-1])
	return plaintext[:(length - unpadding)]
}

func isEncrypted(data string) bool {
	if strings.HasPrefix(data, "ENC(") && strings.HasSuffix(data, ")") {
		return true
	}
	return false
}

func encryptPbe(pbeconfig, plaintext string) (string, error) {
	if pbeconfig == "" {
		return plaintext, errors.New("pbeconfig not found")
	}
	finalKey := pbeconfig
	for i := 0; i < iterationCount; i++ {
		tmpKey := sha256.Sum256([]byte(finalKey))
		finalKey = string(tmpKey[:])
	}

	//block大小和初始向量大小一定要一致
	iv := []byte("\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00")
	block, err := aes.NewCipher([]byte(finalKey))
	if err != nil {
		return "", err
	}
	//填充原文
	blockSize := block.BlockSize()
	padData := pKCS7Padding([]byte(plaintext), blockSize)

	cipherText := make([]byte, len(padData))

	mode := cipher.NewCBCEncrypter(block, iv)
	mode.CryptBlocks(cipherText[:], padData)

	return "ENC(" + base64.StdEncoding.EncodeToString(cipherText) + ")", nil
}

func decryptPbe(pbeconfig, chipertext string) (string, error) {
	if !isEncrypted(chipertext) {
		return chipertext, nil
	}

	if pbeconfig == "" {
		return chipertext, errors.New("pbeconfig not found")
	}

	base64ciphertext := chipertext[4 : len(chipertext)-1]
	ciperBytes, err := base64.StdEncoding.DecodeString(base64ciphertext)
	if err != nil {
		return "", err
	}

	finalKey := pbeconfig
	for i := 0; i < iterationCount; i++ {
		tmpKey := sha256.Sum256([]byte(finalKey))
		finalKey = string(tmpKey[:])
	}

	//block大小和初始向量大小一定要一致
	iv := []byte("\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00")
	block, err := aes.NewCipher([]byte(finalKey))
	if err != nil {
		return "", err
	}
	plainBytes := make([]byte, len(ciperBytes))
	mode := cipher.NewCBCDecrypter(block, iv)
	mode.CryptBlocks(plainBytes, ciperBytes)

	return string(pKCS7UnPadding(plainBytes)), nil
}

func doEncrypt(pbeconfig, plaintext string) {
	enc, err := encryptPbe(pbeconfig, plaintext)
	if err != nil {
		fmt.Println(err)
	} else {
		fmt.Println(enc)
	}
}

func doGetPlain(pbeconfig, secretDir, service string) {
	passwordFilePath, ok := servicePasswordFileMap[service]
	passwordConent, err := ioutil.ReadFile(filepath.Join(secretDir, passwordFilePath))
	if err != nil {
		fmt.Println("read password file error:", err)
		return
	}

	if !ok {
		fmt.Printf("not support to get password of %s \n", service)
		return
	}
	plain, err := decryptPbe(pbeconfig, strings.TrimSpace(string(passwordConent)))
	if err != nil {
		fmt.Println(err)
	} else {
		fmt.Println(plain)
	}
}

func processEncSecrets(encSecrets []string) error {
	for _, encplain := range encSecrets {
		var enc, plain string
		switch parts := strings.SplitN(encplain, ":", 2); len(parts) {
		case 1:
			enc, plain = parts[0], parts[0]+"_plain"
		case 2: //nolint:gomnd // TODO Refactor?
			enc, plain = parts[0], parts[1]
		}

		encContent, err := ioutil.ReadFile(enc)
		if err != nil {
			return err
		}

		plainContent, err := decryptPbe(pbeconfig, string(encContent))
		if err != nil {
			return err
		}
		err = ioutil.WriteFile(plain, []byte(plainContent), os.ModePerm)
		if err != nil {
			return err
		}
	}
	return nil
}
