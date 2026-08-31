# TokenStep 0.2.13

TokenStep 0.2.13 restores automatic updates for users blocked by the missing Apple notarization ticket in the 0.2.12 release artifacts.

## Fixed

- Rebuild the current TokenStep app as version 0.2.13 with Developer ID signing, Apple notarization, and stapled tickets on both the app and DMG.
- Users on 0.2.11 can install this update without disabling Gatekeeper or changing macOS security settings.
- Keep the Trojan Inferno flame-animation and popover-flash fixes from 0.2.12 unchanged.

## Release safety

- Public packaging now requires explicit version, signing identity, notarization credentials, release notes, and an available macOS distribution-policy checker.
- Every app, ZIP, and DMG must pass code-signature, notarization-ticket, Gatekeeper, version, Team ID, and isolated update-installer verification.
- GitHub Releases are created as drafts, downloaded again, checksum-verified, and only then published as Latest.

Token totals, costs, quotas, rankings, collectors, settings, and theme behavior are unchanged.
