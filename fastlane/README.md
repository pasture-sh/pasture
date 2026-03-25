fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios certs

```sh
[bundle exec] fastlane ios certs
```

Sync code signing certificates and profiles (App Store)

### ios build_ios

```sh
[bundle exec] fastlane ios build_ios
```

Build the iOS app (no upload)

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build and upload to TestFlight

### ios release

```sh
[bundle exec] fastlane ios release
```

Submit the already-uploaded build for App Store review (metadata managed in ASC)

### ios test

```sh
[bundle exec] fastlane ios test
```

Run unit tests on simulator

----


## Mac

### mac certs

```sh
[bundle exec] fastlane mac certs
```

Sync macOS certificates and profiles

### mac build_mac

```sh
[bundle exec] fastlane mac build_mac
```

Build the macOS Helper app (no upload)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
