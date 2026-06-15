# Self-Hosting Baby Tracker

This app is fully open source. You can run your own backend and build your own copy of the app — no dependency on the official App Store version's servers.

## What you need

- [Flutter](https://flutter.dev/docs/get-started/install) 3.44+
- [Supabase CLI](https://supabase.com/docs/guides/cli) — for local dev or deploying to cloud
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) — for local Supabase
- Apple Developer account — for iOS builds and Apple Sign-In
- Google Cloud account — for Google Sign-In (free)

---

## Option A: Local development (no cloud account needed)

```bash
git clone https://github.com/YOUR_FORK/baby-tracker
cd baby_tracker

# Start local Supabase (Docker must be running)
supabase start

# Copy and fill in your build-time variables
cp .dart-defines.example .dart-defines
# SUPABASE_URL and SUPABASE_ANON_KEY are pre-filled with local defaults

# Run the app
flutter pub get
flutter run --dart-define-from-file=.dart-defines
```

---

## Option B: Your own cloud Supabase

1. Create a free project at [supabase.com](https://supabase.com)

2. Link and push the schema:
   ```bash
   supabase link --project-ref YOUR_PROJECT_REF
   supabase db push
   ```

3. In the Supabase dashboard, enable auth providers:
   - **Apple**: Authentication → Providers → Apple → enable, add your Service ID + secret
   - **Google**: Authentication → Providers → Google → enable, add your web client ID + secret
   - See [docs/social_auth_setup.md](./social_auth_setup.md) for credentials setup

4. Copy `.dart-defines.example` to `.dart-defines` and fill in your project's URL and anon key:
   ```
   SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
   SUPABASE_ANON_KEY=your-anon-key-from-supabase-dashboard
   ```

5. Build:
   ```bash
   flutter run --dart-define-from-file=.dart-defines
   ```

---

## CI/CD (GitHub Actions)

Store these in **GitHub → Settings → Secrets**:

| Secret | Where to find it |
|--------|-----------------|
| `SUPABASE_URL` | Supabase dashboard → Settings → API |
| `SUPABASE_ANON_KEY` | Supabase dashboard → Settings → API |
| `GOOGLE_IOS_CLIENT_ID` | Google Cloud Console → Credentials |
| `GOOGLE_SERVER_CLIENT_ID` | Google Cloud Console → Credentials |
| `GOOGLE_SERVICE_INFO_PLIST` | Full contents of `GoogleService-Info.plist` |

See `.github/workflows/build.yml` for the build pipeline.

---

## Security model

This app uses [Row Level Security (RLS)](https://supabase.com/docs/guides/auth/row-level-security) — the anon key in the Flutter app is **intentionally public**. It only grants access to data the logged-in user owns. The real security lives in the database policies in `supabase/migrations/`.

---

## Schema changes

All database schema is version-controlled in `supabase/migrations/`. To apply migrations to your cloud project:

```bash
supabase db push
```

To create a new migration locally:

```bash
supabase migration new your_migration_name
# edit the generated file in supabase/migrations/
supabase db reset   # applies all migrations to local DB
```
