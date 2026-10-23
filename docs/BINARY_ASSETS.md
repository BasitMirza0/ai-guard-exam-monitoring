# Binary asset inventory

Inventory of the 38 binary files in the sanitized source snapshot at the audit
pass. Sizes are approximate bytes. The checker scanned text files for secret
patterns but skipped these binaries. Visual inspection found the app icon is the
AI Guard shield/lettermark and the iOS launch image uses that mark; no account
photos, screenshots, videos, model weights or private media are present.

| Path | Type | Approx. size | Purpose / review |
| --- | --- | ---: | --- |
| `android/app/src/main/res/mipmap-hdpi/ic_launcher.png` | PNG | 3.4 KB | Android launcher icon, density variant |
| `android/app/src/main/res/mipmap-mdpi/ic_launcher.png` | PNG | 2.2 KB | Android launcher icon, density variant |
| `android/app/src/main/res/mipmap-xhdpi/ic_launcher.png` | PNG | 4.8 KB | Android launcher icon, density variant |
| `android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png` | PNG | 6.8 KB | Android launcher icon, density variant |
| `android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png` | PNG | 8.7 KB | Android launcher icon, density variant |
| `assets/branding/app-icon.png` | PNG | 43.4 KB | Shared AI Guard shield/lettermark app icon |
| `assets/fonts/PlusJakartaSans.ttf` | TrueType font | 176.3 KB | Bundled application typography; accompanying `assets/fonts/OFL.txt` documents SIL OFL 1.1 |
| `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png` | PNG | 43.4 KB | iOS App Store icon; same size as shared app icon |
| `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png` | PNG | 0.8 KB | iOS app icon, 20 pt @1x |
| `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png` | PNG | 1.8 KB | iOS app icon, 20 pt @2x |
| `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png` | PNG | 2.8 KB | iOS app icon, 20 pt @3x |
| `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png` | PNG | 1.3 KB | iOS app icon, 29 pt @1x |
| `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png` | PNG | 2.6 KB | iOS app icon, 29 pt @2x |
| `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png` | PNG | 4.4 KB | iOS app icon, 29 pt @3x |
| `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png` | PNG | 1.8 KB | iOS app icon, 40 pt @1x |
| `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png` | PNG | 3.9 KB | iOS app icon, 40 pt @2x |
| `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png` | PNG | 5.9 KB | iOS app icon, 40 pt @3x |
| `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png` | PNG | 5.9 KB | iOS app icon, 60 pt @2x |
| `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png` | PNG | 8.8 KB | iOS app icon, 60 pt @3x |
| `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png` | PNG | 3.7 KB | iOS/iPad app icon, 76 pt @1x |
| `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png` | PNG | 7.4 KB | iOS/iPad app icon, 76 pt @2x |
| `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png` | PNG | 8.2 KB | iPad app icon, 83.5 pt @2x |
| `ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png` | PNG | 6.4 KB | Branded iOS launch image, base scale |
| `ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@2x.png` | PNG | 12.4 KB | Branded iOS launch image, @2x |
| `ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png` | PNG | 17.5 KB | Branded iOS launch image, @3x |
| `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png` | PNG | 103.0 KB | macOS application icon, 1024 px |
| `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png` | PNG | 5.7 KB | macOS application icon, 128 px |
| `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png` | PNG | 0.5 KB | macOS application icon, 16 px |
| `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png` | PNG | 14.1 KB | macOS application icon, 256 px |
| `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png` | PNG | 1.1 KB | macOS application icon, 32 px |
| `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png` | PNG | 36.4 KB | macOS application icon, 512 px |
| `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_64.png` | PNG | 2.2 KB | macOS application icon, 64 px |
| `web/favicon.png` | PNG | 4.0 KB | Browser favicon |
| `web/icons/Icon-192.png` | PNG | 8.7 KB | Flutter web app icon |
| `web/icons/Icon-512.png` | PNG | 21.0 KB | Flutter web app icon |
| `web/icons/Icon-maskable-192.png` | PNG | 8.7 KB | Maskable Flutter web icon |
| `web/icons/Icon-maskable-512.png` | PNG | 21.0 KB | Maskable Flutter web icon |
| `windows/runner/resources/app_icon.ico` | ICO | 33.8 KB | Windows application icon |

These are ordinary app branding, font and platform launcher assets. No
suspicious/private binary was identified in the inventory. Preserve the icon
variants because the platform asset catalogs reference their different sizes.
Do not treat this inventory as a license grant: use the bundled OFL for the
font and check any separately sourced artwork before publication.
