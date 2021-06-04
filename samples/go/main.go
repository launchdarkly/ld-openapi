package main

import (
	"context"
	"fmt"
	"os"

	ldapi "github.com/launchdarkly/api-client-go"
)

func main() {
	apiKey := os.Getenv("LD_API_KEY")
	if apiKey == "" {
		panic("LD_API_KEY env var was empty!")
	}
	client := ldapi.NewAPIClient(ldapi.NewConfiguration())
	ctx := context.WithValue(context.Background(), ldapi.ContextAPIKey, ldapi.APIKey{
		Key: apiKey,
	})

	// Create a multi-variate feature flag
	body := ldapi.GlobalFlagRep{
		Name: "Test Flag Go",
		Key:  "test-go",
		Variations: []ldapi.VariateRep{
			{Value: intfPtr([]interface{}{1, 2})},
			{Value: intfPtr([]interface{}{3, 4})},
			{Value: intfPtr([]interface{}{5})}}}
	flag, _, err := client.DefaultApi.ApiV2FlagsProjKeyPost(ctx, body, "openapi", nil)
	if err != nil {
		panic(fmt.Errorf("create failed: %s", err))
	}
	fmt.Printf("Created flag: %+v\n", flag)
	// Clean up new flag
	defer func() {
		if _, err := client.DefaultApi.ApiV2FlagsProjKeyKeyDelete(ctx, "openapi", body.Key); err != nil {
			panic(fmt.Errorf("delete failed: %s", err))
		}
	}()
}

func intfPtr(i interface{}) *interface{} {
	return &i
}
