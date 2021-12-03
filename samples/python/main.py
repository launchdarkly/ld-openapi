from __future__ import print_function
import os
from pprint import pprint

import launchdarkly_api
from launchdarkly_api.model.variation import Variation
from launchdarkly_api.model.feature_flag_body import FeatureFlagBody
from launchdarkly_api.api import feature_flags_api
from launchdarkly_api.rest import ApiException

configuration = launchdarkly_api.Configuration()
configuration.api_key['ApiKey'] = os.getenv("LD_API_KEY")

# Uncomment below to setup prefix (e.g. Bearer) for API key, if needed
# configuration.api_key_prefix['ApiKey'] = 'Bearer'


# Enter a context with an instance of the API client
with launchdarkly_api.ApiClient(configuration) as api_client:
    # Create an instance of the API class
    api_instance = feature_flags_api.FeatureFlagsApi(api_client)

    project_key = "openapi"
    flag_key = "test-python"

    # Create a flag with json variations
    flag_post = FeatureFlagBody(
        name=flag_key,
        key=flag_key,
        variations=[
            Variation(value=[1, 2]),
            Variation(value=[3, 4]),
            Variation(value=[5]),
        ])

    try:
        api_response = api_instance.post_feature_flag(project_key, flag_post)
        pprint(api_response)
    except ApiException as e:
        print("Exception creating flag: %s\n" % e)

    # Clean up the flag
    try:
        api_response = api_instance.delete_feature_flag(project_key, flag_key)
        pprint(api_response)
    except ApiException as e:
        print("Exception deleting flag: %s\n" % e)
