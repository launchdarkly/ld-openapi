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

	auth := make(map[string]ldapi.APIKey)
	auth["ApiKey"] = ldapi.APIKey{
		Key: apiKey,
	}

	ctx := context.WithValue(context.Background(), ldapi.ContextAPIKeys, auth)

	flagName := "Test Flag Go"
	flagKey := "test-go"
	// Create a multi-variate feature flag
	valOneVal := []int{1, 2}
	valOne := map[string]interface{}{"one": valOneVal}
	valTwoVal := []int{4, 5}
	valTwo := map[string]interface{}{"two": valTwoVal}
	body := ldapi.GlobalFlagRep{
		Name: &flagName,
		Key:  &flagKey,
		Variations: &[]ldapi.VariateRep{
			{Value: &valOne},
			{Value: &valTwo},
		},
	}
	flag, _, err := client.DefaultApi.ApiV2FlagsProjKeyPost(ctx, "openapi").GlobalFlagRep(body).Execute()
	if err != nil {
		panic(fmt.Errorf("create failed: %s", err))
	}
	fmt.Printf("Created flag: %+v\n", flag)
	// Clean up new flag
	defer func() {
		if _, err := client.DefaultApi.ApiV2FlagsProjKeyKeyDelete(ctx, "openapi", *body.Key).Execute(); err != nil {
			panic(fmt.Errorf("delete failed: %s", err))
		}
	}()
}

func intfPtr(i interface{}) *interface{} {
	return &i
}
