var LaunchDarklyApi = require('launchdarkly-api');

var defaultClient = LaunchDarklyApi.ApiClient.instance;

var Token = defaultClient.authentications['Token'];
Token.apiKey = process.env.LD_API_KEY;

var apiInstance = new LaunchDarklyApi.FeatureFlagsApi();

const projectName = "openapi";
const keyName = "test-javascript";

var callback = function(error, data) {
  if (error) {
    console.error(error);
    process.exit(1);
  } else {
    console.log('API called successfully. Returned data: ' + JSON.stringify(data));
  }
};

var postCallback = function(error, data) {
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
