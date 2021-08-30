import { FeatureFlagsApi, FeatureFlagsApiApiKeys, FeatureFlagBody } from "launchdarkly-api-typescript";

let apiInstance = new FeatureFlagsApi();
const apiKey = process.env.LD_API_KEY || '';
apiInstance.setApiKey(FeatureFlagsApiApiKeys.Token, apiKey);

const successCallback = function(data){
    console.log('API called successfully. Returned data: ' + JSON.stringify(data));
};
const errorCallback = function(error) {
    console.error('Error!', error);
    process.exit(1);
};

const createSuccessCallback = function(data){
    successCallback(data);

    // Clean up
    apiInstance.deleteFeatureFlag(projectName, keyName).then(successCallback, errorCallback);
};

const projectName = "openapi";
const keyName = "test-typescript";
const flagBody: FeatureFlagBody = {
    name: "Test Flag Typescript",
    key: keyName,
    variations: [{value: [1, 2]}, {value: [3, 4]}, {value: [5]}]
};

apiInstance.postFeatureFlag(projectName, flagBody).then(createSuccessCallback, errorCallback);
