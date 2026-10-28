# VasFlow — Flutter + Supabase

Client, workflow and document management app. Android first.

## Status (Phase 1)

See the checklist in the chat that came with this ZIP. In short: build errors fixed
in the Dart code, GitHub Actions workflow added, demo login removed. **Nothing in
this project has been compiled or run by the person who prepared it** — the first
real result is your own GitHub Actions run.

## Build the APK from your phone (GitHub Actions)

1. Put these files in your GitHub repository (replace the old ones).
2. In the repo on github.com: Settings → Secrets and variables → Actions →
   New repository secret. Add two secrets:
   - `SUPABASE_URL` — your project URL, like `https://abcd1234.supabase.co`
   - `SUPABASE_ANON_KEY` — the **anon / publishable** key (never the service_role key)
3. Open the Actions tab → "Android build" → Run workflow (or just push a commit).
4. When it finishes with a green tick, open the run, scroll to **Artifacts**, and
   download `vasflow-apk`. It is a .zip; open it in your Files app and install
   `app-release.apk` (allow "install unknown apps" if Android asks).

If the run fails, open the red step, find the FIRST line that says `Error:` and send
it. Do not send the whole log.

## Supabase setup

1. Create a Supabase project.
2. SQL Editor → paste all of `supabase/schema.sql` → Run.
3. Authentication → create/sign up your user, then make yourself admin with the
   `update public.profiles ...` command at the bottom of `schema.sql`.
4. Authentication → URL Configuration: set the Site URL. Configure custom SMTP for
   reliable password-reset emails.

## Project layout

```text
lib/            Dart source (main.dart, app.dart, screens/, models/, services/)
test/           Automated tests
supabase/       schema.sql (tables + Row Level Security)
tool/           prepare_android.sh (creates android/ and adds the INTERNET permission)
.github/workflows/android-build.yml
```

The `android/` folder is not stored in this repo; the workflow creates it on every
build with `flutter create`.

## Not done yet

Workspace membership and shared staff access, invites, document vault, payments,
real task storage, reports, offline sync queue, audit log, password-reset screen
inside the app, AI assistant backend. The local cache on the phone is **not
encrypted**.
