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

## Supabase setup (run BOTH SQL files, in this order)

1. Create a Supabase project.
2. SQL Editor → paste all of `supabase/schema.sql` → Run.
3. SQL Editor → paste all of `supabase/phase3_workspaces.sql` → Run. This adds
   workspaces, Admin/Staff roles and invite codes.
4. SQL Editor → paste all of `supabase/phase4_features.sql` → Run. This adds
   applications, payments, documents (with the private `client-documents`
   storage bucket) and makes the `clients` table support archiving and the
   extra profile/details fields.
5. In the app: create an account, log in, and choose **Create workspace**. The person
   who creates it is the Admin. Staff join with an invite code from Settings.
6. Authentication → URL Configuration: set the Site URL. Configure custom SMTP for
   reliable password-reset emails.

## Deadline reminders (experimental)

Tasks and application deadlines schedule **local phone reminders** (the day
before a due date, plus an "overdue" morning nudge the next day at 08:00).
They use `flutter_local_notifications`; `tool/prepare_android.sh` adds the
`POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED` and receiver entries, and the
app asks for the Android 13+ notification permission the first time a reminder
is scheduled. Settings → "Deadline reminders" can turn them off. Honest
caveats: reminders are created while the app is open; there is no server push
system yet; exact scheduling behaviour varies across devices and vendors and
is not verified on a real device. The AI tab is a designed placeholder — it
never reads client data and is clearly marked "not connected yet".

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

## Themes (Stage 1)

Settings → Appearance has three themes: Light, Dark and Liquid Glass. The choice is
saved on the phone. The brand colour is #0BA84A. Liquid Glass uses translucent panels,
a light blur on the main cards, and a soft gradient behind every page. Check how it
looks and performs on your own phone.

## Not done yet

Changing a member's role or removing staff, offline sync queue, audit log,
password-reset screen inside the app, JSONB queries on the client profile
details, AI assistant backend and server push notifications. Reminders are
experimental (see above). The local cache on the phone is **not encrypted**.
