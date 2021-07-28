# Load the gem
require 'launchdarkly_api'
require 'launchdarkly_api/models/variate_rep'

# Setup authorization
LaunchDarklyApi.configure do |config|
  config.api_key['ApiKey'] = ENV['LD_API_KEY']
  config.debugging = true
end

api_instance = LaunchDarklyApi::FeatureFlagsApi.new

project_key = "openapi"
flag_key = "test-ruby"

# Create a flag with a json variations
body = LaunchDarklyApi::FlagPost.new(
  name: "test-ruby",
  key: flag_key,
  variations: [
    LaunchDarklyApi::VariateRep.new({value: [1,2]}),
    LaunchDarklyApi::VariateRep.new({value: [3,4]}),
    LaunchDarklyApi::VariateRep.new({value: [5]}),
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
