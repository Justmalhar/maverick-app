# Packaging & Distribution

Scripts for building and distributing the Maverick apps.

| Script | Purpose |
|--------|---------|
| `make-dmg.sh` | Build `MaverickAgent` (macOS), Developer-ID sign + notarize, and produce `dist/MaverickAgent.dmg` |
| `package.sh` | Build macOS `.app`/`.zip` and the iOS Simulator `.app` |
| `testflight.sh` | Archive + upload `MaverickRemote` to TestFlight |
| `run-agent.sh` | Run the agent locally for development |

## Building a shareable macOS DMG

```bash
./scripts/make-dmg.sh                 # build, sign, notarize, staple, package
./scripts/make-dmg.sh --no-build      # repackage an existing dist/MaverickAgent.app
./scripts/make-dmg.sh --no-notarize   # Developer-ID sign but skip notarization
```

Output: `dist/MaverickAgent.dmg`. Open it, drag the app onto the **Applications**
alias, then share the `.dmg` with anyone.

The script auto-detects whether it can produce a fully distributable build and
degrades gracefully:

| What's available | Result |
|------------------|--------|
| Developer ID cert **+** notary profile | Signed, notarized, stapled — opens cleanly on any Mac |
| Developer ID cert only | Signed but not notarized — Gatekeeper may still warn |
| Neither | Apple-Development signed — for your own machine only |

## One-time setup for distribution to other Macs

Notarization needs **(1)** a Developer ID Application certificate and **(2)**
stored notarization credentials. Both require your paid Apple Developer account.

### 1. Create a "Developer ID Application" certificate

Easiest path (Xcode):

1. Xcode → **Settings… → Accounts**
2. Select your Apple ID → your team → **Manage Certificates…**
3. Click **+** → **Developer ID Application**
4. It's added to your login keychain. Confirm with:

   ```bash
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```

(Alternative: create it on the [Apple Developer portal](https://developer.apple.com/account/resources/certificates) from a CSR, then download + double-click to install.)

### 2. Store notarization credentials

Create an **app-specific password** at <https://appleid.apple.com> →
Sign-In and Security → App-Specific Passwords. Then:

```bash
xcrun notarytool store-credentials "maverick-notary" \
  --apple-id "you@example.com" \
  --team-id "R6G234T379" \
  --password "abcd-efgh-ijkl-mnop"   # the app-specific password
```

This saves the profile in your keychain; `make-dmg.sh` picks it up automatically.

> Prefer an App Store Connect API key? Use
> `--key`, `--key-id`, and `--issuer` instead of `--apple-id`/`--password`.

After both steps, just run `./scripts/make-dmg.sh` and you get a clean,
notarized DMG.
