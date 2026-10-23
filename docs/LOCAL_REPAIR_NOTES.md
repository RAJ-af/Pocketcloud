# Local repair notes

This source update addresses the Flutter errors visible in the supplied GitHub Actions screenshots:

- Replaced removed `FilePicker.platform` / `FilePickerResult` usage with `FilePicker.pickFile()` and `FilePicker.pickFiles()` APIs from file_picker v13.
- Reads selected file content through `PlatformFile.readAsBytes()` / `readAsByteStream()` so Android Storage Access Framework picks are handled without assuming a direct filesystem path.
- Checks the upload's reported and actual byte length against the 25 MiB transfer limit and sanitizes the filename before transfer.
- Streams vault imports into a temporary app-private file and renames it after a successful copy, avoiding whole-file RAM loads and partial visible files.
- Migrated vault sharing to `SharePlus.instance.share(ShareParams(...))`.
- Made the WebRTC chunk authorization expression explicitly boolean and checked both sides of the pairing for upload/list/download requests.
- Restores the app-process host listener when Home reloads a device already marked server-enabled, and exposes sign-out from Home.

## Verification status

- `scripts/verify_source.py`: passed.
- Dart delimiter scan: passed (all `.dart` files have balanced brackets/strings under the source scan).
- Added `test/vault_store_test.dart`; **not executed**.
- `dart format`, `dart analyze`, `flutter test`, and `flutter build apk --release`: **not run** because this workspace has no Flutter/Dart SDK and cannot resolve the Flutter download host.

This is a source repair ZIP, not a verified release build. The GitHub Actions workflow remains the required compile/test gate.
