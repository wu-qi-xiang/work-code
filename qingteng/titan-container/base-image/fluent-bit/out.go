package main

import (
	"C"
	"log"
	"time"
	"unsafe"

	"github.com/fluent/fluent-bit-go/output"
)
import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
)

// openfiles example: {"20210813":{"gateway.request.log": *os.File}}
var openFiles = make(map[string]map[string]*os.File)

// 最大200M
const maxLogSize int64 = 200 * 1024 * 1024

//export FLBPluginRegister
func FLBPluginRegister(def unsafe.Pointer) int {
	return output.FLBPluginRegister(def, "outfile-day", "outfile by day")
}

//export FLBPluginInit
func FLBPluginInit(plugin unsafe.Pointer) int {
	path := output.FLBPluginConfigKey(plugin, "path")
	log.Printf("[outfile-day] path = %q", path)
	// Set the context to point to any Go variable
	output.FLBPluginSetContext(plugin, path)

	go func() {
		for {
			time.Sleep(5 * time.Minute)
			checkOpenFiles()
		}
	}()

	return output.FLB_OK
}

//export FLBPluginFlush
func FLBPluginFlush(data unsafe.Pointer, length C.int, tag *C.char) int {
	log.Print("[outfile-day] Flush called for unknown instance")
	return output.FLB_OK
}

//export FLBPluginFlushCtx
func FLBPluginFlushCtx(ctx, data unsafe.Pointer, length C.int, tag *C.char) int {
	path := output.FLBPluginGetContext(ctx).(string)
	//log.Printf("[outfile-day] Flush called for path: %s", path)

	dec := output.NewDecoder(data, int(length))

	day := getToday()
	logBuffer := new(bytes.Buffer)

	for {
		ret, _, record := output.GetRecord(dec)
		if ret != 0 {
			break
		}

		logMsg, ok := record["log"]
		if !ok {
			continue
		}
		if value, ok := logMsg.(string); ok {
			logBuffer.WriteString(value)
			logBuffer.WriteByte('\n')
			//log.Printf("[outfile-day] write to : %s", fullpath)
		} else if value, ok := logMsg.([]byte); ok {
			logBuffer.Write(value)
			logBuffer.WriteByte('\n')
			//log.Printf("[outfile-day] write to : %s", fullpath)
		} else {
			log.Printf("[outfile-day] not string or []byte : %v", logMsg)
			continue
		}
	}

	file, fullpath, err := openFile(path, day, C.GoString(tag))
	if err != nil {
		log.Printf("[outfile-day] open %s failed:%v", fullpath, err)
		return output.FLB_ERROR
	}

	logBuffer.WriteTo(file)
	return output.FLB_OK
}

//export FLBPluginExit
func FLBPluginExit() int {
	log.Print("[outfile] Exit called for unknown instance")
	return output.FLB_OK
}

//export FLBPluginExitCtx
func FLBPluginExitCtx(ctx unsafe.Pointer) int {
	return output.FLB_OK
}

func openFile(path, day, tag string) (*os.File, string, error) {
	fullpath := filepath.Join(path, day, tag)

	dayFiles, ok := openFiles[day]
	// 说明目录可能还没创建
	if !ok {
		err := os.Mkdir(filepath.Join(path, day), os.ModePerm)
		if err != nil && os.IsNotExist(err) {
			return nil, fullpath, err
		}

		dayFiles = make(map[string]*os.File)
		openFiles[day] = dayFiles
	}

	file, ok := dayFiles[fullpath]
	if !ok {
		// 说明文件还没打开过，打开
		file, err := os.OpenFile(fullpath, os.O_WRONLY|os.O_CREATE|os.O_APPEND, 0664)
		if err != nil {
			return nil, fullpath, err
		}

		dayFiles[fullpath] = file
	}

	return file, fullpath, nil
}

// 后台任务，定期关闭一些过期的文件
func checkOpenFiles() {
	defer func() {
		// 有异常则恢复，避免崩溃
		if err := recover(); err != nil {
			log.Printf("[outfile-day] checkOpenFiles error: %v", err)
			return
		}
	}()

	log.Print("checkOpenFiles begin")
	today := getToday()

	for day, dayfiles := range openFiles {
		if day != today {
			time.Sleep(1 * time.Minute)
			for _, file := range dayfiles {
				file.Close()
			}

			delete(openFiles, day)
		} else {
			for fullPath, file := range dayfiles {
				fileInfo, err := file.Stat()
				if err != nil {
					log.Printf("[outfile-day] Stat %s failed, will remove from openFiles", fullPath)
					delete(dayfiles, fullPath)
					file.Close()
					continue
				}
				if fileInfo.Size() > maxLogSize {
					newPath := fmt.Sprintf("%s.%d", fullPath, time.Now().Unix())
					err := os.Rename(fullPath, newPath)
					if err != nil {
						log.Printf("[outfile-day] rename %s failed", fullPath)
					}
					delete(dayfiles, fullPath)
					file.Close()
					continue
				}
			}
		}
	}
}

func getToday() string {
	nowTime := time.Now().UTC().Add(8 * time.Hour)
	return nowTime.Format("20060102")
}

func main() {
}
