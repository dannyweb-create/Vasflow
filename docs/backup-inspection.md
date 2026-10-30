# VasFlow — Cloud backup & restore: Phase 1 inspection report

Date: 2026-10-30 · Status: inspection only (no files changed, no SQL executed, nothing
committed). Phase A implementation is pending approval.

## Phase A status (APPROVED AND WRITTEN — awaiting your review)

- **File:** `supabase/phase5_backup.sql` (new, idempotent; nothing existing is
  modified). It has **not** been executed against Supabase.
- **Purpose:** creates the backup-history table `workspace_backups`, its indexes and
  constraints, the private `workspace-backups` storage bucket, the 50-completed-backups
  history cap (a guard trigger that blocks the 51st `completed` row — it never deletes),
  and the minimal RLS + storage policies for that one table and bucket.
- **Authorization model (server-side):**
  - Read/list backup metadata → any `is_workspace_member` of that workspace.
  - Create / update / delete backup rows → `is_workspace_admin` only.
  - Read / upload / replace / delete backup ZIPs in storage → admins of the workspace
    that owns the first path folder; upload/update additionally enforce the exact
    path shape `<workspace uuid>/<backup uuid>.zip` (2 folders, both uuid).
  - Row CHECK constraints bind `storage_path` to the row's own `workspace_id`.
- **Run order at manual execution time:** `schema.sql` arc (already applied) →
  `phase3_workspaces.sql` (already applied — do not rerun) → `phase4_features.sql`
  (STILL pending on the live project) → `phase5_backup.sql` (this file, last).
  `phase5_backup.sql` reuses `public.uuid_or_null` from phase 4 and the phase 3
  helpers, so it must come after them.
- **Manual Supabase steps still required before Phase B can be used on a real
  backend:** run `phase4_features.sql`, then `phase5_backup.sql`, in the Supabase
  SQL Editor, and confirm no policy-name clash errors appear.
- **Idempotency:** `create … if not exists` / `on conflict (id) do nothing` for
  table/index/bucket; `drop policy if exists … ; create policy …` for the 8 new
  policies (names unique to Phase 5); `create or replace function`; `drop trigger
  if exists; create trigger`. Static review found: no `drop table` / `truncate` /
  `delete from` / `alter` of existing tables, no `security definer`, no
  `service_role`, no grants to `public`/`anon` (rules target `authenticated`), and
  a balanced function body.
- **Known Phase-B obligations this migration intentionally defers to the app:**
  at the 50-completed cap the app must delete the oldest completed record AND its
  storage file together before finalizing a new backup; deletes of files and rows
  are admin-only and explicit everywhere.

## A. Existing backup-related functionality

At the cloud level there is **no backup or restore system anywhere in the project**.
Everything that exists today is export-shaped or cache-shaped:

- **CSV exports** (clients / applications / payments) via `lib/utils/file_export.dart`
  (`exportCsv`, `saveBytes`) — user saves files to the device. No automation, no
  document files included, and the **`profile` JSONB details column is not exported**.
- **`saveBytes`** — one document download at a time, fully manual.
- **`LocalStore` caches** — `vasflow_clients_v1`, `vasflow_applications_v1`,
  `vasflow_payments_v1`, `vasflow_documents_v1`, `vasflow_tasks_v1` (all optional-JSON)
  in `lib/services/local_store.dart`. These are unencrypted device caches with a
  `clear()` method. They are **not backups**: no recovery path, wiped with app data.
- **Client "Archive / Restore client" toggle** (`clients_screen.dart`, backed by the
  `clients.archived` column + `setArchived`) — list-hiding only, unrelated to backup.
- No backup tables, storage bucket, workflows, or code exist. A project-wide search
  for backup/restore terms matched only the client-archive UI strings.

## B. Data and files that must be included

| Source | Location today | Notes |
|---|---|---|
| Workspace settings | `workspaces` | name etc.; single row per workspace |
| Members & invites | `workspace_members`, `workspace_invites` | restoring into a *new* workspace requires fresh invites |
| Clients (all fields) | `clients` | id, owner_id, full_name, email, phone, country, university, visa_status, passport_number, notes, stage, updated_at, **`archived` bool**, **`profile` jsonb** |
| Applications | `client_applications` | workspace_id, client_id, application_type, country, institution, course, intake, status, submission_date, deadline, updated_at |
| Payments | `client_payments` | amounts, paid date, reference, fee type |
| Documents metadata | `client_documents` | workspace_id, client_id, name, category, **file_path**, mime_type, size_bytes, uploaded_by, updated_at |
| **Document bytes** | storage bucket `client-documents` | paths `<workspace_id>/<client_id>/<uuid>-<name>.ext` (private, RLS-guarded) |
| Tasks / follow-ups / reminder schedule | **device-only** `LocalStore` (`vasflow_tasks_v1`) | tasks are **not in Supabase** because of a serializer field mismatch that was sidestepped; the backup must snapshot them into the manifest (a future `client_tasks` server table is the clean fix) |

Not recoverable today if the phone or access is lost: **tasks** (device-only) and
**document files** (server-side but with no bulk export).

## C. Required database and storage changes

As one **new, idempotent** migration — `supabase/phase5_backup.sql` — touching nothing
that exists (run order: schema.sql alters → phase4_features.sql → phase5_backup.sql):

1. **Table `workspace_backups`**
   - Columns: `id uuid`, `workspace_id uuid not null` → `workspaces(id) on delete
     cascade`, `created_by uuid default auth.uid() → auth.users(id)`,
     `kind text` ('manual' | 'auto'), `status text`
     ('pending' | 'running' | 'completed' | 'failed'), `manifest_sha256 text`,
     `size_bytes bigint`, `record_count int`, `file_count int`, `storage_path text`,
     `error text`, `started_at`, `finished_at`, `created_at timestamptz`.
   - Index on `workspace_id`.
2. **New private storage bucket `workspace-backups`** (`insert into storage.buckets …
   on conflict (id) do nothing`), with folder-prefix policies using the phase-4
   pattern: path `<workspace_id>/<backup_id>.zip`,
   `public.uuid_or_null((storage.foldername(name))[1])` decides authorization.

No changes to existing tables, existing policies, or the `client-documents` bucket.

## D. Security and RLS policies

- **Backup rows:** workspace members may `select` their own workspace's backups;
  **only workspace admins** (`is_workspace_admin`) may `insert`/`delete`. Others' rows
  are invisible at the database level (RLS) — cross-account enumeration fails closed.
- **Backup binaries:** `workspace-backups` bucket policies restricted to admins whose
  workspace id matches the first path folder. Reading the ZIP, uploading it, and
  creating **signed download links** all happen through the storage API with the
  user's own JWT — that is exactly what `createSignedUrl` uses; links stay private,
  short-lived, and are never persisted.
- **Restore authorization:** server-side, every write happens into tables guarded by
  the existing workspace policies, so a restore is impossible into a workspace the
  admin does not govern by database rules. Re-checks in code are defense-in-depth.
- **No service-role keys in the app** — unchanged principle. `AppConfig`
  (`String.fromEnvironment`) stays build-time-only; GitHub Actions secrets flow only
  into dart-defines.
- Sensitive content protection: manifest checksums; error rows store messages, not
  data dumps.

## E. Proposed backup and restore architecture

**BackupService (in-app, running as the signed-in admin; zero service-role use):**

1. Snapshot phase: read every workspace-scoped row through the existing RLS'd
   repositories (`client_repository.dart`, `business_repositories.dart` — generic
   `WorkspaceTable<T>`), including the `archived` flag and `profile` JSONB map.
2. Files phase: download every document from `client-documents` (batched to keep
   memory bounded), computing per-file `sha256`.
3. Manifest `v1` JSON: workspace, members, invites, tasks (from `LocalStore`),
   clients(+details), applications, payments, documents metadata; every record keeps
   its **original `id`** and `updated_at`; manifest has all checksums, counts, version,
   created_at, created_by, schema summary.
4. Assemble a single ZIP: `manifest.json` + `files/…` → compute ZIP `sha256`
   (`manifest_sha256`).
5. Upload ZIP → `workspace-backups/<workspace_id>/<backup_id>.zip`; write the backup
   row through status transitions **pending → running → completed** (size, counts,
   checksum) or **failed** (error message, cleanup attempt of partial upload).

**RestoreService (admin-only):**

1. Download the chosen archive (history list or by download URL).
2. **Integrity gate**: recompute ZIP sha256 and per-entry checksums; any mismatch
   aborts before writing anything.
3. **Preview diff**: record counts in the manifest vs. current workspace rows shown
   before any write.
4. Two strategies:
   - **Restore into a new workspace** (recommended default — phone-loss transfer,
     recovery-after-access-loss).
   - **Restore into the current workspace** — requires typed confirmation.
5. Idempotent writes: **upserts keyed on original IDs** (PostgREST `onConflict`) so a
   retried restore never duplicates; application-ordered writes:
   workspace → members → clients → applications → payments → documents metadata;
   document bytes re-uploaded to stable paths, skipping when sha256 matches the
   existing object; **restore never deletes anything** — accidental overwrite
   protection comes from the confirmation wall + upsert/non-destructive design.
6. Result summary screen (restored/failed counts per type) and a
   `failed`-status audit trail.

**Automatic backups:** schedule config (Off / Daily / Weekly) stored on the device
(`LocalStore`, e.g. `vasflow_backup_settings_v1`). Runs at app-open when the last
completed backup is older than the interval. True server-side cron (unattended daily
backups) is a *separate future decision* — it needs a deployed Edge Function and is
not promised here.

**Download / recovery path:** history list → signed `createSignedUrl` → save via
`file_export.dart saveBytes`; README "Backups & recovery" section documents
phone-loss recovery (sign in as the same admin on the new phone and restore), with
note IDs and relationships.

## F. Implementation phases and tests

1. **Phase A — migration `supabase/phase5_backup.sql`**: `workspace_backups` +
   `workspace-backups` bucket + RLS/storage policies. Nothing renamed or altered.
2. **Phase B — Dart services**: `BackupRepository` (row CRUD via RLS),
   `BackupService` (snapshot, sha256, ZIP, upload, status transitions),
   `RestoreService` (verify → preview → idempotent restore), settings in `LocalStore`.
   Preserve honest status labels; backups never silently overwrite.
3. **Phase C — UI (Settings/Profile tab)**: "Backups & recovery" section — Backup
   now; history (time, status icon, size, error line, download link); auto schedule
   selector; restore flow with managed dialogs progressing *preview → confirm →
   progress → summary*.
4. **Phase D — automatic backups on app open** + README recovery guide.
5. **Tests** — unit: manifest round-trip; sha256 verify / tamper detection; status
   transitions; restore idempotency (double restore = same count); task map
   serialization. **Device checklist:** backup → delete a client → restore → verify
   counts and relations; second account must fail to list/restore; signed URL
   expires; storage-full and mid-restore failure paths; retry after failure corrects
   `failed` rows; restore into a fresh workspace then switch workspace.

## G. Risks and unresolved questions

1. **Memory vs scale** — assembling one ZIP of very large workspaces in-app may hit
   background memory limits; the batching/zip-bundler toolset (zip package) needs
   forging. Attachment: keep per-file batches; if needed, assemble per-file and
   document limits.
2. **Cross-workspace restores** — restore into *another existing* workspace is
   deliberately not implemented in Phase 1 (new-workspace restore covers migration);
   a later decision.
3. **Tasks server table** — tasks effectively live on the device; the manifest
   keeps them (mitigating-summary becomes a separate flow) — the phase-6 flow
   `client_tasks` server table remains the cleaner, longer-term fix.
4. **Unattended server-side cron** — a truly automatic daily backup cannot work
   without a deployed Edge Function; until then, backups only occur when the app is
   opened. This must be communicated in Settings text.
5. **DoS/abuse** — an admin could spam backups; an optional row-count cap
   (e.g. 50 completed per workspace) and exact bucket size monitoring are cheap and
   warned against for Phase 1; not mandatory.
6. **Large file downloads** — archived bytes ride through `createSignedUrl`; no
   resumable/chunked download; acceptable in Phase 1, item is on record for later.
7. **What counts as "completed" for auto-sched?** — last manual backup counts too, or
   only auto? Login note: only completed rows count, either kind.
8. **Restore into current workspace** — inherently risky; typed confirmation, warning
   dialogs, and, honest copy (existing records with the same IDs get overwritten —
   the only equality-delete behavior is none).

## Phase B status (APPROVED AND IMPLEMENTED — Dart services only)

Phase B delivers the backup/restore engine. **No UI exists yet (Phase C) and
nothing has been verified against a live Supabase project** — "works" below
means "compiles clean, analyzer clean, unit-tested locally".

### What was built
- `lib/services/backup_models.dart` — manifest v1 (format string + version
  gate, checksums, counts), `BackupEntry` (history row parser, tolerant of
  messy values), `RestorePreview` (`ready` = manifest checksum matched AND all
  file checksums verified), `RestoreResult`, and the pure `BackupPlanner`
  helpers: workspace retargeting, foreign-key relaxation, document path
  mapping, ZIP key naming, task merging (device rows always win, nothing
  deleted).
- `lib/services/backup_repository.dart` — `workspace_backups` rows + storage:
  list / createWaiting / status transitions / countCompleted /
  oldestCompleted / pathFor (`<workspace>/<uuid>.zip` — the exact shape the
  storage policies enforce) / uploadZip (upsertBinary, application/zip) /
  downloadZip / deleteFileThenRow (file removed first, so no orphaned file
  can outlive its row) / signed URL provider, all through the signed-in
  user's own permissions. `errorText` trims any thrown error to the 2000-char
  column limit and strips exception wrappers.
- `lib/services/backup_service.dart` — one `run()` that: guards non-admin and
  offline states; makes room when ≥50 completed rows exist (deletes the
  oldest row + its storage file together; if the server-side cap trigger
  still fires from a concurrent backup, prunes once and finalizes again);
  snapshots workspace row, membership (list_team() for admins, own row as
  fallback), and **raw rows** of clients / client_applications /
  client_payments / client_documents so every column survives (price tables
  not included), merges device-only tasks verbatim; downloads every document
  from `client-documents` (missing files become manifest `missing_files`
  entries, never silently skipped); builds manifest.json + per-file sha256 +
  manifest sha256; assembles the ZIP in memory and uploads it; status
  transitions are pending → running → completed or failed (error message
  stored); **an interrupted run can never be marked completed**.
- `lib/services/restore_service.dart` — `prepare()` downloads the archive,
  verifies `manifest.sha256` against the history row (damaged/replaced
  archives are refused), verifies every file checksum, and collects a
  preview (per-type manifest counts vs live server counts fetched through
  normal RLS reads). `performRestore()` writes in parent-first order
  (clients → applications → payments → documents) with `upsert(onConflict:
  'id')` — retries never duplicate and nothing is deleted; foreign-key
  failures fall back per-row with optional user references stripped; document
  files re-upload to the target workspace path (skipped when the server
  already holds the same-size file); LocalStore tasks merge in-device with
  device rows winning (restored tasks get their reminders re-armed on the
  next Tasks screen open, because the tasks screen syncs all tasks on load).
  A device-carried archive path exists for fresh-device recovery.

### Phase B test results (local, no Supabase)
- `dart analyze` — No issues found.
- `dart format` — all Phase B files formatted.
- `flutter test` — 20/20 passing, incl. 12 new focused tests: sha256 known
  vector, manifest round-trip, version/format rejection, stable document keys
  (path traversal resistant), retargeting purity, soft-FK stripping, task
  merge idempotency (device-wins, retries add nothing), 3-folder document
  path shape, history row parsing tolerance, 2000-char error trim, ZIP
  round-trip with checksum equality, preview refusing on checksum problems.

### Data and limitations still open in Phase B (honest list)
- **Workspace name and members:** restores never rewrite the workspace row,
  and other people's memberships cannot be recreated by the app
  (`workspace_members` has no client insert policy); a restored *new*
  workspace contains only the restoring admin. Invites are not backed up
  (hashed, ephemeral).
- **Reminders:** task rows restore fine, but application-deadline reminders
  have no scheduler hookup yet (see earlier gaps) and caches are
  re-fetched on app open, not pushed proactively.
- **Memory:** the ZIP is assembled/downloaded fully in RAM at both ends —
  very large workspaces may need streaming work (documented Phase 1 risk).
- **Auto backups:** Off/Daily/Weekly scheduling belongs to Phase D (with the
  UI); nothing runs unattended yet.
- **Phase C obligations:** restore strategies and confirmations are service-
  level only; typed same-workspace confirmations, history UI and signed-link
  download UI come with the screens.

### Security notes carried into review
- Everything uses the signed-in user's session; there is no service-role key
  and no RLS bypass anywhere in the new code. Client-side guards (admin
  checks, workspace id sources) are habits only — the server policies remain
  the real enforcement.
- The `created_by` forgeability issue on insert (recorded under Phase A
  risks) still exists at the SQL level.
- The manifest is validated against the history row's checksum, but the row
  itself is admin-writable; a workspace admin can always replace their own
  backup — accepted design boundary.
- Restore writes are re-validated server-side on every upsert even when the
  service is handed an arbitrary workspace id: cross-workspace forgery cannot
  get past RLS.

## Phase C status (APPROVED AND IMPLEMENTED — Backup & Recovery UI)

The screens wrap the Phase B services 1:1 and add no new server calls of
their own. Everything runs with the signed-in user's session only.

- `lib/screens/backup_screen.dart` — History (status, manual/automatic kind,
  timestamp, record/file/size chips, colored error text), manual "Back up
  now" with live step progress (via the new `onStep` callback on
  BackupService.run), success/failure feedback, per-entry Archive download
  (FilePicker save), Restore flow, and Delete (file first, then row).
- Restore flow inside the screen: checksum-gated prepare → preview dialog
  (incoming counts vs live server counts through RLS read) → strategy picker
  (RadioGroup) → typed `RESTORE` confirmation (default strategy for a
  workspace-less account is a NEW workspace; accounts already in a workspace
  see that option disabled with an explanation) → progress dialog → result
  dialog (written counts, row failures, file failures, retry-safety note).
  Damaged archives are refused with a file-problem list before anything
  opens. Missing document files from the backup are explained before
  confirmation. Records are never deleted; matching IDs overwrite in place.
- `lib/screens/settings_screen.dart` — new "Backups & recovery" tile
  (visible to everyone; the screen itself demotes staff to read-only).
- `lib/services/backup_service.dart` — added the informational `onStep`
  progress callback; run() logic unchanged (20 Phase B tests still pass).
- `test/backup_screen_test.dart` — pure-data and widget tests: size
  formatting, status labels, kind labels, new-workspace gating, stable
  download file names, offline notice, and the Settings entry point (tap →
  BackupScreen renders).
- Verification: `dart format` clean · `dart analyze` → No issues found ·
  `flutter test` → 26/26 passed (12 backup service, 6 backup UI, 8 other).

### Phase C limitations (honest)
- Still **not verified end-to-end** against a live Supabase project; phases
  4 (old features) and 5 (backup SQL) remain unexecuted in the SQL editor.
- The progress indicator is step-based, not byte-accurate (the service has
  no byte-level progress hooks).
- Same-workspace restore requires no Supabase writes beyond the restore
  itself, but the confirmation is purely client-side — as with everything,
  the server RLS remains the real enforcement.
- Deleting running backups is possible for admins while a backup is
  uploading; the history card hides actions only for non-completed rows'
  restore button, not delete (delete of a running row is safe server-side
  because the cap trigger and policies gate it, but the UI does not
  specially test that race).
---
