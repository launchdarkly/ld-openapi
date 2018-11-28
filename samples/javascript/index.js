var LaunchDarklyApi = require('launchdarkly-api');

var defaultClient = LaunchDarklyApi.ApiClient.instance;

var Token = defaultClient.authentications['Token'];
Token.apiKey = process.env.LD_API_KEY;

var apiInstance = new LaunchDarklyApi.FeatureFlagsApi();

var callback = function(error, data) {
  if (error) {
    console.error(error);
  } else {
    console.log('API called successfully. Returned data: ' + JSON.stringify(data));
  }
};

const projectName = "openapi";
const keyName = "test-javascript";

apiInstance.postFeatureFlag(projectName,
  {
    name: "Test Flag Javascript",
    key: keyName,
    variations: [{value: [1, 2]}, {value: [3, 4]}, {value: [5]}]
  }, {}, callback);

// Clean up new flag (requires a new api instance)
apiInstance = new LaunchDarklyApi.FeatureFlagsApi();
apiInstance.deleteFeatureFlag(projectName, keyName, callback);
