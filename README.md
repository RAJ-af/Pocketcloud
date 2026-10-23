# PocketCloud

**Turn a spare Android phone into a personal cloud host.** PocketCloud is a Flutter Android MVP with Supabase email/password authentication, consent onboarding, device pairing, a local private vault, WebRTC signalling and an attempted peer-to-peer file transfer path.

> **Status: source-complete prototype, not production-ready.** This repository has not been compiled or executed with Flutter in the current environment because the Flutter/Dart SDK is unavailable here. The Supabase project and migration are not deployed yet. The remote WebRTC path is implemented in source but has not been validated on two physical devices or across restrictive networks. Do not interpret source code or a passing static check as proof of real-world connectivity.

## What is in the repo

- Modern dark Flutter UI with mango-lime accent: setup, email/password auth, consent onboarding, server dashboard, paired-device list, QR/code pairing, vault and security screen.
- Per-install identifier persisted in Android secure storage; device names and status metadata live in Supabase.
- Consent version records for acceptance and rejection. Full policy drafts are readable from onboarding and are also stored in `docs/`.
- A user-selected app-private vault with import, list, share/export and delete functionality.
- 12-character pairing secret; only a SHA-256 digest is stored. The database sets the five-minute expiry using its own clock.
- Edge Function source for atomic, single-use pairing redemption and server-side device revocation.
- RLS on all seven application tables, explicit grants, owner-scoped policies and consent checks.
- WebRTC offer/answer/ICE signalling source and data-channel transfers with permission checks, a 25 MiB file limit, SHA-256 integrity checks, ordered chunk checks, bounded reconnect attempts and access-lease checks.
- GitHub Actions workflow to create Android scaffold if required, analyse, test, build a release APK and upload it as an artifact.

## Known MVP boundaries

- **Keep PocketCloud open on the server phone.** No Android foreground service, reboot start or OEM battery-survival guarantee is included. Force-stop and power loss stop service.
- **Only files explicitly imported into PocketCloud's app-private vault are exposed.** Android protects other apps' private data and the OS is not remotely controlled.
- **A pair supports one active peer connection at a time in this version.** Multiple registered pairings may exist, but concurrent host sessions are not a release claim.
- **Direct WebRTC can fail behind restrictive NAT/mobile networks.** A TURN relay is optional and not provisioned by this repository. Without TURN, cross-network connection success is not guaranteed.
- Upload is disabled by default and is allowed only when the server owner enables it at pairing time.
- The vault is app-private, but not an additional app-layer encrypted vault. Android's storage encryption depends on OS/device settings.
- Account deletion, retention automation, rate limiting, abuse monitoring, external security review and legal review are not yet complete.

## Setup Supabase

1. Create a **new, separate Supabase project** in an organization you control. For India, `ap-south-1` is a reasonable initial region.
2. Apply `supabase/migrations/20261024000100_pocketcloud_core.sql` once using the SQL Editor or Supabase CLI. Review the SQL first and do not apply it to an unrelated production project.
3. Deploy both Edge Functions: `redeem-pairing` and `revoke-device`. The included `supabase/config.toml` requires JWT verification for both. Supabase-managed environment variables must include `SUPABASE_URL`, `SUPABASE_ANON_KEY` or `SUPABASE_PUBLISHABLE_KEY`, and `SUPABASE_SERVICE_ROLE_KEY`. Never place the service-role key in Flutter, GitHub Actions variables, or this repo.
4. Enable Email in Supabase Auth. For public release enable email confirmation, configure transactional SMTP, check rate limits and test password reset. Check Database → Publications contains `public.signaling_messages`.
5. Run Supabase Security Advisor and Performance Advisor. Confirm all seven app tables have RLS and explicit grants, and test with two accounts.
6. Add `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` as GitHub Actions **Variables**. Only add TURN settings if you operate a TURN server; use short-lived credentials rather than a permanent credential in the APK.

Detailed steps and expected database behaviour: [`docs/SETUP_SUPABASE.md`](docs/SETUP_SUPABASE.md), [`docs/DATABASE.md`](docs/DATABASE.md), [`docs/SECURITY.md`](docs/SECURITY.md).

## Build locally

Install Flutter stable and Android build tools first. Then run:

```bash
flutter create --platforms=android --org dev.pocketcloud --project-name pocketcloud .
python3 scripts/prepare_android_manifest.py
flutter pub get
flutter analyze
flutter test
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://YOUR_REF.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_YOUR_KEY
```

The publishable key identifies the project and may be embedded in the client when RLS is correctly configured. **Never** use `service_role`, `sb_secret_...`, a database password or a Supabase personal access token as a Dart define. Dart defines can be extracted from the APK.

## Build through GitHub Actions

1. Upload this folder to your own GitHub repository.
2. Add repository Actions variables `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`.
3. Open **Actions → Android APK → Run workflow** or push a change to `main`/`master`.
4. Wait for the actual job result. Download the `pocketcloud-release-apk` artifact from that run and install it on a test device.
5. Check all CI steps and test auth, policy consent, pairing, revoke, import, download and upload on at least two physical devices. A successful APK build does not prove network traversal works.

The workflow creates Android platform scaffold on its first run if the `android/` folder is absent. The initial repository intentionally keeps generated Android build files out of the package.

## Security summary

- Auth uses Supabase email/password sessions; row policies use `auth.uid()` plus ownership predicates.
- Every public application table has RLS; `anon` grants are revoked and authenticated privileges are limited. The migration does not allow client inserts into `device_pairs` or client updates to pairing-code state.
- Pair redemption and device revocation are performed by JWT-verified Edge Functions calling service-role-only atomic Postgres functions. The SQL RPCs run as invoker, not as publicly executable `SECURITY DEFINER` functions.
- Device activity timestamps are stamped by the database. The secure local installation ID is not stored in user metadata.
- Signalling rows carry session metadata, not file contents. Remote file transfers enforce direction, pair permissions, file size and SHA-256 digest checks.
- Full consent is checked at the UI and database/RPC boundary. A user who rejects the current version remains locked out of server features.

Read [`docs/TEST_PLAN.md`](docs/TEST_PLAN.md) before calling this complete. The repository is an engineering starting point, not a security certification or legal document prepared by counsel.
