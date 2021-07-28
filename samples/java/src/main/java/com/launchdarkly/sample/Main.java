package com.launchdarkly.sample;

import com.launchdarkly.api.ApiClient;
import com.launchdarkly.api.ApiException;
import com.launchdarkly.api.Configuration;
import com.launchdarkly.api.auth.*;
import com.launchdarkly.api.model.*;
import com.launchdarkly.api.api.FeatureFlagsApi;
import java.util.*;

public class Main {
    private static final String PROJECT_KEY = "openapi";
    private static final String FLAG_KEY = "test-java";

    public static void main(String[] args) {
        ApiClient defaultClient = Configuration.getDefaultApiClient();
        
        ApiKeyAuth Token = (ApiKeyAuth) defaultClient.getAuthentication("ApiKey");
        System.out.println("KEY " + System.getenv("LD_API_KEY"));
        Token.setApiKey(System.getenv("LD_API_KEY"));

        FeatureFlagsApi apiInstance = new FeatureFlagsApi();

        FlagPost body = new FlagPost()
            .name(FLAG_KEY)
            .key(FLAG_KEY)
            .variations(Arrays.<VariateRep>asList(
                new VariateRep().value(Arrays.<Integer>asList(1,2)),
                new VariateRep().value(Arrays.<Integer>asList(3,4)),
                new VariateRep().value(Arrays.<Integer>asList(5))
            ));
        try {
            apiInstance.postFeatureFlag(PROJECT_KEY, body, null);
            apiInstance.deleteFeatureFlag(PROJECT_KEY, FLAG_KEY);
        } catch (ApiException e) {
            // Make sure the ld-openapi build fails if an api exception is thrown
            throw new RuntimeException(e);
        }
    }
}
