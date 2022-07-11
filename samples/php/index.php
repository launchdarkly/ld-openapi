<?php
require_once(__DIR__ . '/vendor/autoload.php');

$PROJECT_KEY = 'openapi';
$FLAG_KEY = 'test-php';

$config = LaunchDarklyApi\Configuration::getDefaultConfiguration()->setApiKey('Authorization', getenv('LD_API_KEY'));


$apiInstance = new LaunchDarklyApi\Api\FeatureFlagsApi(
    new GuzzleHttp\Client(),
    $config
);

$feature_flag_body = (new \LaunchDarklyApi\Model\FeatureFlagBody())
    ->setKey($FLAG_KEY)
    ->setName($FLAG_KEY)
    ->setVariations(
        [
            (new \LaunchDarklyApi\Model\Variation())
                ->setValue([1,2]),
            (new \LaunchDarklyApi\Model\Variation())
                ->setValue([3,4]),
            (new \LaunchDarklyApi\Model\Variation())
                ->setValue([4,5]),
        ]
    );

try {
    $result = $apiInstance->postFeatureFlag($PROJECT_KEY, $feature_flag_body);
    print_r($result);
} catch (Exception $e) {
    echo 'Exception creating flag: ', $e->getMessage(), PHP_EOL;
}

try {
    $result = $apiInstance->deleteFeatureFlag($PROJECT_KEY, $FLAG_KEY);
} catch (Exception $e) {
    echo 'Exception deleting flag: ', $e->getMessage(), PHP_EOL;
}
