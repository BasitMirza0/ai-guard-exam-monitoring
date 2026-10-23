"""Copy real iOS OAuth configuration from a downloaded Firebase plist.

Run from the project root after enabling Google authentication in Firebase:
  python3 tool/configure_ios_google_sign_in.py
Does not invent credentials or alter Android/Firebase Dart options.
"""

from pathlib import Path
import plistlib

ROOT = Path(__file__).resolve().parents[1]
source = ROOT / 'ios/Runner/GoogleService-Info.plist'
target = ROOT / 'ios/Runner/Info.plist'
with source.open('rb') as file:
    firebase = plistlib.load(file)
with target.open('rb') as file:
    info = plistlib.load(file)

client = firebase.get('CLIENT_ID')
reversed_client = firebase.get('REVERSED_CLIENT_ID')
if not client or not reversed_client:
    raise SystemExit(
        'No changes made: GoogleService-Info.plist lacks CLIENT_ID or '
        'REVERSED_CLIENT_ID. Enable Google in Firebase Authentication, then '
        'download the iOS app plist again.'
    )
if firebase.get('BUNDLE_ID') != 'com.example.aicheat':
    raise SystemExit(
        'No changes made: the plist bundle ID differs from com.example.aicheat. '
        'Update the Xcode bundle ID and Firebase iOS Dart options consistently '
        'before adapting this script.'
    )
if reversed_client != '.'.join(reversed(client.split('.'))):
    raise SystemExit('No changes made: CLIENT_ID and REVERSED_CLIENT_ID disagree.')

info['GIDClientID'] = client
urls = info.setdefault('CFBundleURLTypes', [])
if not any(reversed_client in entry.get('CFBundleURLSchemes', []) for entry in urls):
    urls.append({
        'CFBundleTypeRole': 'Editor',
        'CFBundleURLSchemes': [reversed_client],
    })
with target.open('wb') as file:
    plistlib.dump(info, file, sort_keys=False)
print('Configured the iOS Google client ID and callback scheme in Info.plist.')
