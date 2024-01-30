# Build a Flutter application for iOS and optionnally publish it to AppStoreConnect

This action builds an application made with Flutter for iOS using Odevio.

If the build type is publication is also publishes it to AppStoreConnect.

## Secrets
### `api-key`
An API key of an Odevio user with access to the application to build.

## Inputs

These values can also be set in a `.odevio` file in the repo to build.

### `api-key`
**Required** An Odevio API key linked to a user that has access to the app to build.

### `app-key`
**Required** The Odevio key of the application you want to publish.

### `build-type`
The build type to run. Defaults to `publication`.
- `ad-hoc`: build the application and get an IPA file to install on your device
- `validation`: build the application, sign it and verify that everything is ready to send to AppStoreConnect, but do not send it
- `publication`: build the application, sign it and send it to AppStoreConnect to make a new public or TestFlight release

### `directory`
The directory of the flutter project in the repo. Defaults to the root directory of the repo.

### `flutter`
The flutter version to use. Defaults to the latest version.

### `minimal-ios-version`
The minimal iOS version for your application (the deployment target in XCode). If not provided, the one defined in the XCode configuration files is used.

### `app-version`
The app version to set for this build. If not provided, the one in pubspec.yaml is used.

### `build-number`
The build number to use for the build. If not provided, the one in pubspec.yaml is used.

### `mode`
The mode to build the app in (release, profile or debug). Defaults to `release`.

### `target`
The main entry-point file of the application. Defaults to `lib/main.dart`

### `flavor`
An optional app flavor.

### `post-build-command`
Optional commands to run after the build is finished, in the mac VM (to send debug files to sentry for example).

## Outputs

### `ipa`
A link to download and install the built API file, for ad-hoc builds.

## Example usage

### Publish to AppStoreConnect
```yaml
name: publish-ios-app
run-name: Publishing application to App Store Connect
on:
  push:
    branches:
      - master # Set the name of the branch where the code to release is pushed
jobs:
  # Add your test steps if needed
  #test:
  # You could also add your play store publish job here
  #publish-android:
  publish-ios:
    # Uncomment if you use the 'test' job
    #needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: Odevio/Odevio-CICD/github-actions/build-ios@v1
        with:
          api-key: ${{ secrets.ODEVIO_API_KEY }}
          app-key: 'AAA'
          build-type: publication
```

### Build for testing
```yaml
name: build-ipa
run-name: Building IPA app
on:
  push:
    branches:
      - dev # Set the name of the branch where the code to test is pushed
jobs:
  # Add your test steps if needed
  #test:
  # You could also add your APK build job here
  #build-android:
  build-ios:
    # Uncomment if you use the 'test' job
    #needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: Odevio/Odevio-CICD/github-actions/build-ios@v1
        id: build
        with:
          api-key: ${{ secrets.ODEVIO_API_KEY }}
          app-key: 'AAA'
          build-type: ad-hoc
      # add step using ${{ steps.build.outputs.ipa }} if you need
```
