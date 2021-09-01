test:
	go mod init example.com
	go mod edit -replace github.com/launchdarkly/api-client-go=$(shell pwd)/../../targets/api-client-go/
	go mod tidy
	go run .
