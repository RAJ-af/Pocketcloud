#!/usr/bin/env python3
"""Add the small set of network / camera declarations used by PocketCloud.
Safe to run repeatedly in CI after `flutter create`; it never replaces the app manifest."""
from pathlib import Path
import re
p = Path('android/app/src/main/AndroidManifest.xml')
if not p.exists():
    raise SystemExit(f'Missing {p}; run `flutter create --platforms=android --org dev.pocketcloud --project-name pocketcloud .` first.')
s = p.read_text()
permissions = [
    'android.permission.INTERNET',
    'android.permission.ACCESS_NETWORK_STATE',
    'android.permission.CAMERA',
]
for permission in permissions:
    tag = f'<uses-permission android:name="{permission}" />'
    if tag not in s:
        s = re.sub(r'(<manifest\b[^>]*>)', r'\1\n    ' + tag, s, count=1)
# Camera is requested only by scanner code. WebRTC cleartext is not enabled.
p.write_text(s)

# flutter_secure_storage 11+ and flutter_webrtc require Android API 23 or newer.
# Keep Flutter's generated build structure but raise a lower default minSdk safely.
for gradle_file in (Path('android/app/build.gradle.kts'), Path('android/app/build.gradle')):
    if not gradle_file.exists():
        continue
    gradle = gradle_file.read_text()
    if gradle_file.suffix == '.kts':
        gradle = re.sub(r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 23', gradle)
        gradle = re.sub(r'minSdk\s*=\s*(?:16|19|21|22)', 'minSdk = 23', gradle)
    else:
        gradle = re.sub(r'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 23', gradle)
        gradle = re.sub(r'minSdkVersion\s+(?:16|19|21|22)\b', 'minSdkVersion 23', gradle)
    gradle_file.write_text(gradle)
