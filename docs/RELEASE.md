# Release Guide

This guide is for maintainers publishing TokenStep for normal macOS users.

## Prerequisites

- Apple Developer Program membership
- Developer ID Application certificate installed in Keychain
- Xcode Command Line Tools
- Notarization credentials configured for `notarytool`

Check local signing identities:

```bash
security find-identity -p codesigning -v
```

## Build and Sign

```bash
TOKENSTEP_VERSION=0.1.0 \
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
./script/package_release.sh
```

This creates:

```text
release/TokenStep-0.1.0.zip
release/TokenStep-0.1.0.dmg
```

## Configure Notarization

Recommended: store credentials in the keychain.

```bash
xcrun notarytool store-credentials tokenstep-notary \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

Then release with notarization:

```bash
TOKENSTEP_VERSION=0.1.0 \
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
TOKENSTEP_NOTARY_PROFILE="tokenstep-notary" \
./script/package_release.sh --notarize
```

Alternatively, pass credentials through environment variables:

```bash
TOKENSTEP_VERSION=0.1.0 \
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
APPLE_ID="you@example.com" \
APPLE_TEAM_ID="TEAMID" \
APPLE_APP_PASSWORD="app-specific-password" \
./script/package_release.sh --notarize
```

Do not commit Apple credentials to the repository.

## Validate

After notarization:

```bash
spctl -a -vv TokenStepSwift/dist/TokenStep.app
spctl -a -vv -t install release/TokenStep-0.1.0.dmg
xcrun stapler validate TokenStepSwift/dist/TokenStep.app
xcrun stapler validate release/TokenStep-0.1.0.dmg
```

## Publish to GitHub

1. Create a GitHub Release for the version tag.
2. Upload the notarized DMG.
3. Upload the ZIP as a fallback artifact.
4. Include a short changelog and supported clients.

## GitHub Actions Release

The repository includes a manual Release workflow. Configure these repository secrets first:

- `CERTIFICATE_P12_BASE64`: base64-encoded Developer ID Application `.p12`
- `CERTIFICATE_PASSWORD`: password for the `.p12`
- `KEYCHAIN_PASSWORD`: temporary CI keychain password
- `CODE_SIGN_IDENTITY`: for example `Developer ID Application: Your Name (TEAMID)`
- `APPLE_ID`: Apple Developer account email
- `APPLE_TEAM_ID`: Apple Developer Team ID
- `APPLE_APP_PASSWORD`: app-specific password for notarization

Then run the `Release` workflow manually with a version number such as `0.1.0`.

Apple's official overview is here: [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution).
