# Overview

This sample application will create and delete a feature flag.

# Running sample

Get dependencies

```
composer update
```

```
LD_API_KEY=<AUTHENTICATION TOKEN> composer test
```

# Testing with a local package

Update `composer.json` to link a local version of the package:

```json
{
  "require": {
    "launchdarkly/api-client-php": "@dev",
    "guzzlehttp/guzzle": "*"
  },
  "repositories": [
    {
        "type": "path",
        "url": "path/to/api-client-php",
        "options": {
            "symlink": true
        }
    }
  ]
}
```

Then update dependencies

```
composer update
```
