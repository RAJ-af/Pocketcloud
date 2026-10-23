# Test plan and hostile-user walkthrough

**All boxes are unchecked until executed against a live environment.** Source presence does not mean a scenario has passed.

## Required environment

- Fresh Supabase staging project with the committed migration and both Edge Functions deployed.
- One test user with current Terms + Privacy consent; a second separate account for isolation tests.
- Two physical Android devices signed into the same test account, preferably on separate network paths as well as same Wi-Fi.
- Release APK built by GitHub Actions, plus device logs and a record of app/OS versions.

## Authentication and consent

- [ ] Valid signup, invalid email, short password and repeated submit.
- [ ] Email confirmation enabled: unconfirmed account cannot use app features.
- [ ] Sign in, wrong password, password reset request, signout and expired session.
- [ ] No configured project URL/key opens the setup screen without crashing.
- [ ] Full Terms and Privacy content can be opened, selected/scrolled and closed on a small display.
- [ ] Accept produces two separate rows with exact current policy versions and DB timestamps.
- [ ] Reject produces false decisions and the protected features remain blocked after rebuild/relaunch.
- [ ] A later reject supersedes an older acceptance for that policy version.
- [ ] Incrementing either policy version forces a fresh decision for that exact policy type.
- [ ] Direct API call without both current acceptances cannot create a device, server code, pair or signal.
- [ ] Client cannot forge `decided_at` or `created_at`; PostgreSQL owns both fields.

## Database / RLS adversarial checks

- [ ] User A cannot select, insert, update or delete User B rows on profiles, consents, devices, pair codes, pairs, signals or events.
- [ ] Anonymous role cannot access app tables; inspect both grants and RLS.
- [ ] `authenticated` cannot select/update/delete pair codes after creation.
- [ ] `authenticated` cannot set pairing status, used time or expiry, even with a crafted REST request.
- [ ] `authenticated` cannot insert into `device_pairs` or change `can_upload`/endpoints/revocation timestamp back to null.
- [ ] Device update cannot clear `revoked_at`; revoked devices cannot turn server mode back on through the normal client API.
- [ ] RPCs reject invocation from `anon` and `authenticated`; only the trusted service-role Edge path can execute them.
- [ ] Update database timestamps spoofed into `devices.last_seen_at` / `updated_at`; trigger must overwrite with DB time.
- [ ] Supabase Security Advisor and Performance Advisor run after migration; record and triage all findings.

## Device registration and pairing

- [ ] Two separate installs produce different stable install IDs; process restart preserves same ID.
- [ ] Reinstall/secure-store reset can create a second row and is handled without pretending it is the old installation.
- [ ] Non-server device, revoked server, revoked client, same-device pair and wrong-account attempt all fail.
- [ ] QR scan and manual code entry produce the same canonical 12-character code behavior.
- [ ] Malformed/expired/replayed code fails generically; no raw code appears in logs or DB.
- [ ] Two redemption requests raced against the same code result in at most one successful redemption.
- [ ] Code expiry is determined by the database clock, not the client clock.
- [ ] Upload permission stays false unless the server owner explicitly enabled it before creating the code.
- [ ] Revoke a device and verify all of its pairs and active pairing codes are revoked by the server transaction.

## Local vault

- [ ] Import text, image, and video; cancel picker without error; handle path unavailable and low storage.
- [ ] Duplicate names from one selection and repeated selections get unique suffixes without overwrite.
- [ ] Empty names, separators, `..`, control chars and very long names remain within vault directory.
- [ ] Share/export and deletion behave on supported Android versions.
- [ ] The app cannot list other apps' private files and does not request broad all-files access.

## Remote WebRTC and file protocol

- [ ] Connect two devices on same Wi-Fi and exchange offer/answer/ICE over Realtime.
- [ ] Connect across Wi-Fi and mobile data; separately test a network where TURN is needed.
- [ ] Server accepts one active peer; a clean hangup or failed connection permits a new paired peer.
- [ ] Expired/stale signalling, wrong pair endpoints, stale candidates and repeated messages are ignored safely.
- [ ] List request works only for an active pair and correct server/client direction.
- [ ] Download succeeds only after a matching request ID is pending; unsolicited `file_start` is rejected.
- [ ] Download denied if `can_download` is false. Upload denied unless `can_upload` is true.
- [ ] Test 0-byte, small and exactly 25 MiB files; reject above-limit file before reading it into memory.
- [ ] Reordered, duplicated, oversized, unknown-ID chunks; false declared length; digest mismatch; invalid transfer UUID all fail closed.
- [ ] Partial or failed transfer never appears as a completed destination file; test disk-full and write failures.
- [ ] Duplicate incoming filenames never overwrite an existing file.
- [ ] Revoke pair during active transfer; validate lease behavior and worst-case delay when signalling is unavailable.
- [ ] Remove network and restore it; reconnect is bounded to eight attempts, no duplicate peer loops, manual Retry works.

## Background and endurance

- [ ] Keep screen on for 30 minutes while server enabled; inspect heartbeat and connections.
- [ ] Screen off, battery saver, Doze, OEM battery optimisation, process death, reboot and force-stop each tested separately.
- [ ] Document that force-stop/power loss is an expected stop in this MVP; no automatic reboot service is promised.

## GitHub release workflow

- [ ] `flutter pub get`
- [ ] `dart analyze`
- [ ] `flutter test`
- [ ] `flutter build apk --release`
- [ ] Workflow artifact exists and installs on Android.
- [ ] Commit `pubspec.lock` after first successful dependency resolution and review dependency/security updates.
- [ ] Real two-device test uses the release APK, not only a debug build.
