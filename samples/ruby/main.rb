# Load the gem
require 'launchdarkly_api'

# Setup authorization
LaunchDarklyApi.configure do |config|
  config.api_key['Authorization'] = ENV['LD_API_KEY']
end

api_instance = LaunchDarklyApi::FeatureFlagsApi.new

project_key = "openapi"
flag_key = "test-ruby"

# Create a flag with a json variations
body = LaunchDarklyApi::FeatureFlagBody.new(
  name: "test-ruby",
  key: flag_key,
  variations: [
    LaunchDarklyApi::Variation.new(value=[1,2]),
    LaunchDarklyApi::Variation.new(value=[3,4]),
    LaunchDarklyApi::Variation.new(value=[5]),
  ])

begin
  result = api_instance.post_feature_flag(project_key, body)
  p result
rescue LaunchDarklyApi::ApiError => e
  puts "Exception creating feature flag: #{e}"
end

# Clean up new flag
begin
  result = api_instance.delete_feature_flag(project_key, flag_key)
  p result
rescue LaunchDarklyApi::ApiError => e
  puts "Exception deleting feature flag: #{e}"
end