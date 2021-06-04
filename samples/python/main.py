from __future__ import print_function
import os
from pprint import pprint

import swagger_client as launchdarkly_api
import swagger_client.models as models
from swagger_client.rest import ApiException

configuration = launchdarkly_api.Configuration()
configuration.api_key['Authorization'] = os.getenv("LD_API_KEY")

client = launchdarkly_api.ApiClient(configuration)
api_instance = launchdarkly_api.DefaultApi(client)

project_key = "openapi"
flag_key = "test-python"

# Create a flag with json variations
feature_flag_body = launchdarkly_api.GlobalFlagRep(
    name=flag_key,
    key=flag_key,
    variations=[
        models.VariateRep(value=[1, 2]),
        models.VariateRep(value=[3, 4]),
        models.VariateRep(value=[5])
    ])

try:
    api_response = api_instance.api_v2_flags_proj_key_post(feature_flag_body, project_key)
    pprint(api_response)
except ApiException as e:
    print("Exception creating flag: %s\n" % e)

# Clean up the flag
try:
    api_response = api_instance.api_v2_flags_proj_key_key_delete(project_key, flag_key)
    pprint(api_response)
except ApiException as e:
    print("Exception deleting flag: %s\n" % e)
