from __future__ import print_function
import os
from pprint import pprint

import launchdarkly_api
from launchdarkly_api.model.variate_rep import VariateRep
from launchdarkly_api.model.global_flag_rep import GlobalFlagRep
from launchdarkly_api.api import default_api
from launchdarkly_api.rest import ApiException

configuration = launchdarkly_api.Configuration()
configuration.api_key['ApiKey'] = os.getenv("LD_API_KEY")

# Uncomment below to setup prefix (e.g. Bearer) for API key, if needed
# configuration.api_key_prefix['ApiKey'] = 'Bearer'


# Enter a context with an instance of the API client
with launchdarkly_api.ApiClient(configuration) as api_client:
    # Create an instance of the API class
    api_instance = default_api.DefaultApi(api_client)

    project_key = "openapi"
    flag_key = "test-python"

    # Create a flag with json variations
    feature_flag_body = GlobalFlagRep(
        name=flag_key,
        key=flag_key,
        variations=[
            VariateRep(value=[1, 2]),
            VariateRep(value=[3, 4]),
            VariateRep(value=[5]),
        ])

    try:
        api_response = api_instance.api_v2_flags_proj_key_post(project_key, feature_flag_body)
        pprint(api_response)
    except ApiException as e:
        print("Exception creating flag: %s\n" % e)

    # Clean up the flag
    try:
        api_response = api_instance.api_v2_flags_proj_key_key_delete(project_key, flag_key)
        pprint(api_response)
    except ApiException as e:
        print("Exception deleting flag: %s\n" % e)
