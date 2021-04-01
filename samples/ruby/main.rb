# Load the gem
require 'swagger_client'

# Setup authorization
SwaggerClient.configure do |config|
  config.api_key['Authorization'] = ENV['LD_API_KEY']
  config.debugging = true
end

api_instance = SwaggerClient::DefaultApi.new

project_key = "openapi"
flag_key = "test-ruby"

# Create a flag with a json variations
body = SwaggerClient::GlobalFlagRep.new(
  name: "test-ruby",
  key: flag_key,
  variations: [
    SwaggerClient::VariateRep.new({value: [1,2]}),
    SwaggerClient::VariateRep.new({value: [3,4]}),
    SwaggerClient::VariateRep.new({value: [5]}),
  ])

begin
  result = api_instance.api_v2_flags_proj_key_post(project_key, body)
  p result
rescue SwaggerClient::ApiError => e
  puts "Exception creating feature flag: #{e}"
end

# Clean up new flag
begin
  result = api_instance.api_v2_flags_proj_key_key_delete(project_key, flag_key)
  p result
rescue SwaggerClient::ApiError => e
  puts "Exception deleting feature flag: #{e}"
end
