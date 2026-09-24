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

## Build Without Publishing

```bash
TOKENSTEP_VERSION=0.2.13 ./script/build_swiftui_and_run.sh --no-launch
```

This produces a local development app only. It does not create anything under `release/` and must not be uploaded as a public build.

## Configure Notarization

Recommended: store credentials in the keychain.

```bash
xcrun notarytool store-credentials tokenstep-notary \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

Every public package is notarized. The release script has no sign-only public mode:

```bash
TOKENSTEP_VERSION=0.2.13 \
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
TOKENSTEP_NOTARY_PROFILE="tokenstep-notary" \
./script/package_release.sh --notarize
```

Alternatively, pass credentials through environment variables:

```bash
TOKENSTEP_VERSION=0.2.13 \
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
APPLE_ID="you@example.com" \
APPLE_TEAM_ID="TEAMID" \
APPLE_APP_PASSWORD="app-specific-password" \
./script/package_release.sh --notarize
```

Do not commit Apple credentials to the repository.

## Validate

The packaging command already runs all of these gates and fails before producing a publishable checksum file if any gate fails:

```bash
./script/verify_release_artifacts.sh \
  release/TokenStep-0.2.13.dmg \
  release/TokenStep-0.2.13.zip \
  0.2.13

./script/verify_update_installer.sh \
  release/TokenStep-0.2.13.dmg \
  0.2.13 \
  TokenStepSwift/dist/TokenStep.app/Contents/Helpers/TokenStepHelper
```

`verify_release_artifacts.sh` requires valid code signatures, stapled notarization tickets, `syspolicy_check distribution`, Gatekeeper assessment, exact version, and the expected Team ID. This remains authoritative even if the maintainer Mac has Gatekeeper assessments disabled.

## Publish to GitHub

Before the release commit, update the release documents (the Release workflow checks the first and last items):

- Add `docs/RELEASE_NOTES_<version>.md` starting with `# TokenStep <version>`.
- Add the version's summary at the top of `CHANGELOG.md`.
- Update the "最新版本" section and the DMG download links in `README.md` to `TokenStep-<version>.dmg`.

1. Merge the release commit to `main` and wait for CI.
2. Run the repository's `Release` workflow from `main` with the exact version.
3. The workflow creates a draft and uploads the notarized DMG, ZIP, and checksum file.
4. The workflow downloads the draft assets, checks their hashes, reruns distribution and isolated-installer verification, and only then publishes the release as Latest.

Do not manually upload artifacts that did not pass this workflow. A failed post-upload check must leave the release as a draft, never as a public release.

## GitHub Actions Release

The repository includes a manual Release workflow. Configure these repository secrets first:

- `CERTIFICATE_P12_BASE64`: base64-encoded Developer ID Application `.p12`
- `CERTIFICATE_PASSWORD`: password for the `.p12`
- `KEYCHAIN_PASSWORD`: temporary CI keychain password
- `CODE_SIGN_IDENTITY`: for example `Developer ID Application: Your Name (TEAMID)`
- `APPLE_ID`: Apple Developer account email
- `APPLE_TEAM_ID`: Apple Developer Team ID
- `APPLE_APP_PASSWORD`: app-specific password for notarization

Then run the `Release` workflow manually from `main` with a version number such as `0.2.13`.

Apple's official overview is here: [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution).
