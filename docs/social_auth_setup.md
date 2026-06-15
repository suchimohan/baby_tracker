# Social Auth Setup

## Apple Sign-In

Apple Sign-In works on the **simulator** with a personal Apple ID today — no registration needed for local testing.

For **production** (App Store):

1. Go to developer.apple.com → **Certificates, IDs & Profiles**
2. Find App ID `io.github.suchimohan.babytracker` → Edit → enable **Sign In with Apple**
3. Create a **Services ID** (e.g. `io.github.suchimohan.babytracker.service`) — used for web redirect flow
4. Create a **Key** with Sign In with Apple enabled → download the `.p8` file
5. In `supabase/config.toml`, set:
   ```toml
   [auth.external.apple]
   enabled = true
   client_id = "io.github.suchimohan.babytracker"
   secret = "env(SUPABASE_AUTH_EXTERNAL_APPLE_SECRET)"
   ```
   The secret format is: `KEY_ID:TEAM_ID:base64(p8-file-contents)`

---

## Google Sign-In

1. Go to console.cloud.google.com → create or select a project
2. **APIs & Services → OAuth consent screen** → External → add your email as a test user
3. **APIs & Services → Credentials → Create Credentials → OAuth client ID**
   - Type: **iOS** → bundle ID: `io.github.suchimohan.babytracker` → saves as **iOS client ID**
4. Create another OAuth client ID:
   - Type: **Web application** → saves as **server client ID** (used by Supabase to verify tokens)
5. Download `GoogleService-Info.plist` and add it to `ios/Runner/` in Xcode
6. Add the `REVERSED_CLIENT_ID` from that plist as a URL scheme in `ios/Runner/Info.plist`
7. In `supabase/config.toml`, add:
   ```toml
   [auth.external.google]
   enabled = true
   client_id = "YOUR_WEB_CLIENT_ID"
   secret = "YOUR_WEB_CLIENT_SECRET"
   skip_nonce_check = true
   ```
8. Pass client IDs to Flutter at build time:
   ```
   flutter run \
     --dart-define=GOOGLE_IOS_CLIENT_ID=YOUR_IOS_CLIENT_ID \
     --dart-define=GOOGLE_SERVER_CLIENT_ID=YOUR_WEB_CLIENT_ID
   ```

---

## Current Status

| Provider | Simulator | Production |
|----------|-----------|------------|
| Apple    | Works now | Needs steps 1–5 above |
| Google   | Needs setup | Needs steps 1–8 above |
