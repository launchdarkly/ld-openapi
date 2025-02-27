import LaunchDarklyApi from 'launchdarkly-api';

const defaultClient = LaunchDarklyApi.ApiClient.instance;

const Token = defaultClient.authentications['ApiKey'];
Token.apiKey = process.env.LD_API_KEY;

const apiInstance = new LaunchDarklyApi.FeatureFlagsApi();

const projectName = "openapi";
const keyName = "test-javascript";

const callback = (error, data) => {
  if (error) {
    console.error(error);
    process.exit(1);
  } else {
    console.log('API called successfully. Returned data: ' + JSON.stringify(data));
  }
};

const postCallback = (error, data) => {
  callback(error, data);

  if (!error) {
    // Clean up
    apiInstance.deleteFeatureFlag(projectName, keyName, callback);
  }
};

apiInstance.postFeatureFlag(projectName,
  {
    name: "Test Flag Javascript",
    key: keyName,
    variations: [{value: [1, 2]}, {value: [3, 4]}, {value: [5]}]
  }, {}, postCallback);