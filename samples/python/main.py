from __future__ import print_function
import os
from pprint import pprint

import launchdarkly_api
import launchdarkly_api.models
from launchdarkly_api.rest import ApiException

configuration = launchdarkly_api.Configuration()
configuration.api_key['Authorization'] = os.getenv("LD_API_KEY")

client = launchdarkly_api.ApiClient(configuration)
api_instance = launchdarkly_api.FeatureFlagsApi(client)

project_key = "openapi"
flag_key = "test-python"

# Create a flag with json variations
feature_flag_body = launchdarkly_api.FeatureFlagBody(
    name=flag_key,
    key=flag_key,
    variations=[
        launchdarkly_api.models.Variation(value=[1, 2]),
        launchdarkly_api.models.Variation(value=[3, 4]),
        launchdarkly_api.models.Variation(value=[5])
    ])

try:
    api_response = api_instance.post_feature_flag(project_key, feature_flag_body)
    pprint(api_response)
except ApiException as e:
    print("Exception creating flag: %s\n" % e)

# Clean up the flag
try:
    api_response = api_instance.delete_feature_flag(project_key, flag_key)
    pprint(api_response)
except ApiException as e:
    print("Exception deleting flag: %s\n" % e)
