import { FeatureFlagsApi, Configuration, FeatureFlagBody } from "launchdarkly-api-typescript";

const apiToken = process.env.LD_API_KEY;
const config = new Configuration({apiKey: apiToken});
let apiInstance = new FeatureFlagsApi(config);

const successCallback = function(res){
    console.log('API called successfully. Returned data: ' + JSON.stringify(res.data));
};
const errorCallback = function(error) {
    console.error('Error!', error);
    process.exit(1);
};

const createSuccessCallback = function(res){
    successCallback(res);

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

apiInstance.deleteFeatureFlag(projectName, keyName)
    .then(() => {
        console.log("flag deleted")
        apiInstance.postFeatureFlag(projectName, flagBody).then(createSuccessCallback, errorCallback);
    })
    .catch((err) => {
        if (err?.response?.status == 404) {
            console.log("No flag to cleanup")
        } else {
            errorCallback(err)
        }
        apiInstance.postFeatureFlag(projectName, flagBody).then(createSuccessCallback, errorCallback);
    })
