from bravado.client import SwaggerClient
from bravado.swagger_model import load_file

# Merely generating a Bravado client is enough to validate the spec.
# Actually using the client is unnecessary.
client = SwaggerClient.from_spec(load_file('./targets/openapi.yaml'))
