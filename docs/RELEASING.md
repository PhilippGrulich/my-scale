# Releasing a new build to TestFlight

Verified end-to-end on 2026-07-05 (build 1.0.0 (1)) and 2026-10-21 (1.0.0 (2), "Mochi"). Fully headless — no Xcode
GUI needed. Written for whoever ships the next build (human or agent).

## One-time state that already exists

| Thing | Value / location |
|---|---|
| ASC app record | **MyOpenScale**, app id `6787745052`, SKU `myopenscale` |
| Bundle ids | `com.philippgrulich.myopenscale.app` (+ `.controls`, `.watchkitapp`) |
| Team | `8M2DN93YKC` |
| ASC API key | `~/.appstoreconnect/private_keys/AuthKey_Z7MX5327NV.p8`, Key ID `Z7MX5327NV`, Issuer ID `7517ab5e-7043-41c4-a30a-306219d14bb9`, role App Manager. **The .p8 is a secret — never commit it** (gitignored). |
| Distribution cert | `Apple Distribution: Philipp Grulich (8M2DN93YKC)` in the login keychain, ASC cert id `W9GF2WWU26`, **expires 2027-07-05** (renewal: see below) |
| Provisioning profiles | "MyOpenScale App Store" / "… Controls App Store" / "… Watch App Store", installed in `~/Library/MobileDevice/Provisioning Profiles/` and `~/Library/Developer/Xcode/UserData/Provisioning Profiles/` |
| TestFlight groups | "Internal" (internal, auto-gets every build; Philipp is a tester) and "Public Beta" (external, public link `https://testflight.apple.com/join/5CVxeYhC`) |

## Why the pipeline looks like this (hard-won)

- Headless `xcodebuild -allowProvisioningUpdates` fails with **"No Accounts"**
  (CLI can't see the Xcode-GUI Apple ID session).
- Xcode *cloud signing* with the API key fails with **"Cloud signing permission
  error"** (needs an Admin-role key; ours is App Manager).
- Workaround that works: the distribution cert + App Store profiles were created
  directly via the ASC REST API, and the export **manually signs** with them.
  Archive signs with the Development cert; only the export re-signs for App Store.

## Ship a build

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ~/projects/my-scale
WORK=$(mktemp -d)
```

1. **Bump the build number** — edit `CURRENT_PROJECT_VERSION` (and
   `MARKETING_VERSION` if it's a new user-facing version) in **all three**
   targets in `project.yml`. Every upload needs a build number App Store
   Connect hasn't seen for that version.

2. **Generate + archive** (the `.xcodeproj` is gitignored, always regenerate):

   ```bash
   xcodegen generate
   xcodebuild archive -project MyOpenScaleApp.xcodeproj -scheme MyOpenScaleApp \
     -configuration Release -destination 'generic/platform=iOS' \
     -archivePath "$WORK/MyOpenScale.xcarchive"
   ```

3. **Export with manual App Store signing.** Write `$WORK/exportOptions.plist`:

   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
     <key>method</key><string>app-store-connect</string>
     <key>teamID</key><string>8M2DN93YKC</string>
     <key>signingStyle</key><string>manual</string>
     <key>signingCertificate</key><string>Apple Distribution</string>
     <key>provisioningProfiles</key>
     <dict>
       <key>com.philippgrulich.myopenscale.app</key><string>MyOpenScale App Store</string>
       <key>com.philippgrulich.myopenscale.app.controls</key><string>MyOpenScale Controls App Store</string>
       <key>com.philippgrulich.myopenscale.app.watchkitapp</key><string>MyOpenScale Watch App Store</string>
     </dict>
     <key>destination</key><string>export</string>
     <key>uploadSymbols</key><true/>
   </dict>
   </plist>
   ```

   ```bash
   xcodebuild -exportArchive -archivePath "$WORK/MyOpenScale.xcarchive" \
     -exportOptionsPlist "$WORK/exportOptions.plist" -exportPath "$WORK/export"
   ```

4. **Upload:**

   ```bash
   xcrun altool --upload-app -f "$WORK/export/MyOpenScaleApp.ipa" -t ios \
     --apple-id 6787745052 \
     --apiKey Z7MX5327NV --apiIssuer 7517ab5e-7043-41c4-a30a-306219d14bb9
   ```

   Pass `--apple-id` (the app's ASC id): without it altool sometimes can't
   find the app record ("Unable to find Apple ID for Bundle ID").

   Processing takes ~2–15 min (poll `GET /v1/builds`, wait for
   `processingState: VALID`). The **Internal** group gets the build
   automatically. Export compliance is auto-answered by
   `ITSAppUsesNonExemptEncryption=false` in the Info.plists.

5. **Release to the public link** — attach the build to the "Public Beta"
   group and submit for beta review (first review took ~a day; follow-ups are
   usually fast):

   ```
   POST /v1/betaGroups/{publicBetaGroupId}/relationships/builds   {"data":[{"type":"builds","id":BUILD_ID}]}
   POST /v1/betaAppReviewSubmissions                              {"data":{"type":"betaAppReviewSubmissions","relationships":{"build":{"data":{"type":"builds","id":BUILD_ID}}}}}
   ```

   Optionally add a `betaBuildLocalizations` "what to test" note first.

## Talking to the ASC API without dependencies

Mint an ES256 JWT with plain `openssl` + python stdlib (15-min lifetime,
`aud: appstoreconnect-v1`, header `kid: Z7MX5327NV`, payload `iss: <issuer id>`;
convert the DER ECDSA signature to raw 64-byte r||s, base64url each part).
Then `curl -H "Authorization: Bearer $TOKEN" https://api.appstoreconnect.apple.com/...`.
(Or `pip install pyjwt cryptography` and use `jwt.encode(..., algorithm="ES256",
headers={"kid": ...})`.)

## When the distribution cert expires (2027-07-05)

Recreate it via the API (App Manager role is sufficient — it's only Xcode
*cloud signing* that demands Admin):

1. `openssl req -new -newkey rsa:2048 -nodes -keyout dist.key -out dist.csr -subj "/CN=.../O=.../C=DE"`
2. `POST /v1/certificates` with `{certificateType: "DISTRIBUTION", csrContent: <CSR PEM>}`
3. base64-decode `certificateContent` → `dist.cer` (DER); `security import` both
   cert and key into the login keychain (`-T /usr/bin/codesign` on the key).
4. Recreate the three profiles: `POST /v1/profiles` with
   `profileType: IOS_APP_STORE`, the bundleId resource id, and the new cert id;
   base64-decode `profileContent` → install under the same profile names in
   both profile directories (names must keep matching `exportOptions.plist`).

## Gotchas

- **`403 FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED`** on upload and on
  every API call: an agreement needs accepting. Check App Store Connect →
  Business (Free Apps agreement **Active**) *and* developer.apple.com →
  Account (updated Program License Agreement, Account Holder only). After
  accepting, it can take a few minutes until uploads go through.
- Adding a build to the **Internal** group via the API returns 422 — expected,
  internal groups get every build automatically.
- A `betaBuildLocalizations` POST for `en-US` can 409 (auto-created): PATCH the
  existing one instead.

- `xcode-select` points at CommandLineTools — always `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Never hand-edit the `.xcodeproj`; edit `project.yml` and re-run `xcodegen generate`.
- Plist keys like `UIBackgroundModes` live in the hand-written root `Info.plist`
  (`GENERATE_INFOPLIST_FILE: NO`) — not in `project.yml`.
- TestFlight builds expire after 90 days; ship a fresh build before then to keep
  the public link working.
