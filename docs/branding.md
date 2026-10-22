# Branding

What the app looks and sounds like: its name, logo, icon, palette, typography and
the artwork around it. Branding has **not** been applied yet — issue #65 tracks
the decisions, and this file is the map for whoever implements them.

Read it before touching an icon, a colour or the app's name, and update it when
branding ships.

## What ships today

| Thing | Today |
| --- | --- |
| Android name | `Read aloud` (`android:label` in `android/app/src/main/AndroidManifest.xml`) |
| iOS name | `Glowing Waffle` (`CFBundleDisplayName` in `ios/Runner/Info.plist`; `CFBundleName` is `glowing_waffle`) |
| macOS name | `glowing_waffle` (`PRODUCT_NAME` in `macos/Runner/Configs/AppInfo.xcconfig`) |
| Web name | `Read aloud` (`web/manifest.json` `name`/`short_name`, `web/index.html` `<title>` and `apple-mobile-web-app-title`) |
| Icon | Flutter's template logo on every platform: `android/app/src/main/res/mipmap-*`, `ios/Runner/Assets.xcassets/AppIcon.appiconset`, `macos/Runner/Assets.xcassets/AppIcon.appiconset`, `web/icons/*`, `web/favicon.png` |
| Android adaptive icon | None — there is no `mipmap-anydpi-v26/`, so Android 8+ masks the legacy bitmap |
| Splash | Flutter template: white Android `launch_background.xml`, iOS `LaunchImage`, no macOS splash |
| Theme | `ColorScheme.fromSeed(seedColor: Colors.deepPurple)` in `lib/app.dart` (Material 3, light only) |
| Fonts | System default; nothing bundled in `pubspec.yaml` |
| Web chrome | `theme_color` / `background_color` = `#0175C2` (Flutter blue) in `web/manifest.json`; `index.html` has no `theme-color` meta |
| Logo / wordmark | None; no artwork in the repository |

## Decisions

1. **Name.** The repository and bundle id say "Glowing Waffle", Android and web
   say "Read aloud". Pick one display name (roughly ≤ 12 characters so it is not
   truncated on a home screen) and keep the store/bundle identifiers in step.
   The **bundle id must stay `dev.luen.glowingwaffle`**: changing it installs a
   second app and abandons the downloaded model (#41).
2. **Logo and icon.** The mark has to read at 48 px. Decide whether it is a
   waffle grid, a speech mark, a monogram, or a wordmark-only treatment, and
   produce a 1024 px master plus:
   - a foreground layer for Android's adaptive icon (safe zone, see below),
   - a monochrome layer for Android 13+ themed icons,
   - a maskable variant for the PWA.
3. **Palette.** Either keep a seeded Material 3 scheme (change the seed) or
   define explicit roles. Today there is no dark scheme; decide whether branding
   includes one. Whatever is chosen, the web manifest colours must match — they
   are still Flutter blue.
4. **Typography.** Bundling a face costs download size and a licence. A display
   face used only for the wordmark is usually enough; body text can stay on the
   system font. Any bundled font goes in `THIRD_PARTY_NOTICES.md` and, if it is
   copyleft, into `LICENSES/` (#32).
5. **Voice and tone.** UI copy is deliberately plain ("Play", "Save WAV",
   "Download model", "Free the archive"). Decide whether branding changes copy
   or only the visuals; the error messages are user-facing and should stay
   literal.
6. **Surrounding artwork.** Store listing (1024 icon, 1024×500 feature graphic),
   GitHub social preview (1280×640), README header, screenshots, and the web
   favicon/apple-touch-icon.

## Where each asset lives

| Surface | Files |
| --- | --- |
| Android icon | `android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png` (48/72/96/144/192 px) |
| Android adaptive icon | add `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` + foreground/background drawables; foreground is a 108×108 dp canvas with a 66 dp safe zone |
| Android splash | `android/app/src/main/res/drawable/launch_background.xml`, `drawable-v21/launch_background.xml`, `values/styles.xml`, `values-night/styles.xml` |
| iOS icon | `ios/Runner/Assets.xcassets/AppIcon.appiconset/` (20–1024 px at 1×/2×/3×; the 1024 must have **no alpha channel**) |
| iOS splash | `ios/Runner/Base.lproj/LaunchScreen.storyboard`, `ios/Runner/Assets.xcassets/LaunchImage.imageset/` |
| iOS name | `ios/Runner/Info.plist` (`CFBundleDisplayName`, `CFBundleName`) |
| macOS icon | `macos/Runner/Assets.xcassets/AppIcon.appiconset/` (16–1024 px; the rounded-rect shape is baked into the artwork) |
| macOS name | `macos/Runner/Configs/AppInfo.xcconfig` (`PRODUCT_NAME`, `PRODUCT_COPYRIGHT`) |
| Web icons | `web/icons/Icon-192.png`, `Icon-512.png`, `Icon-maskable-192.png`, `Icon-maskable-512.png`, `web/favicon.png` |
| Web chrome | `web/manifest.json` (`name`, `short_name`, `theme_color`, `background_color`, `icons[].purpose`), `web/index.html` (`<title>`, `description`, `apple-mobile-web-app-title`, add `theme-color`) |
| Theme | `lib/app.dart` — `ThemeData(colorScheme: ColorScheme.fromSeed(...))`; add `darkTheme`/`themeMode` if a dark scheme is in scope |
| Android name | `android:label` in `android/app/src/main/AndroidManifest.xml` |
| README | the `# Glowing Waffle – Read aloud` heading and any header image |

Keep the **source artwork** (SVG or a 1024 px master) in `docs/branding/` so the
per-size PNGs are always reproducible, and commit that master with the exports.
Never hand-edit the generated sizes.

The maskable PWA icons already exist but the manifest does not mark them
`"purpose": "maskable"`; add that with the branding pass.

## Constraints

- **Do not bundle the speech models as assets.** `pubspec.yaml` deliberately has
  no `assets:` for them (#6, #7); branding artwork is small and is the only kind
  of asset that belongs there.
- **Keep the release APK small.** It is built arm64-v8a only (#40, #46); a
  multi-megabyte font family for a wordmark is not worth it.
- **Contrast matters more than the palette.** The app shows errors inline
  (`text_tab.dart` uses `colorScheme.error`), a model setup card and playback
  controls; check all three in light mode, and in dark mode if one is added.
- **Platform icon rules are not suggestions.** iOS rejects a 1024 icon with
  alpha; macOS expects the rounded rect in the art; Android's adaptive
  foreground is cropped to a circle/squircle by the launcher; a maskable PWA
  icon needs its content inside the central ~80%.
- **Names are duplicated in five places.** Use the tables above as a checklist;
  a rename that misses one is invisible until someone looks at that platform.

## Verifying a branding change

```sh
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64   # Android icon + splash
flutter build web --release                                   # manifest, icons, title
flutter build macos --release                                 # macOS icon
flutter build ios --no-codesign                               # iOS icon (Xcode renders it)
```

For Android, the quickest check is `adb install -r` and looking at the launcher,
then cold-starting the app to see the splash colour. For web, open
`build/web/manifest.json` and the browser tab.

## When branding lands

- [ ] One name in all five places (Android, iOS, macOS, web, README).
- [ ] Icons exported from one master: Android legacy + adaptive + monochrome,
      iOS (no alpha on 1024), macOS, web normal + maskable, favicon.
- [ ] Splash/launch backgrounds use the brand colour, light and dark.
- [ ] Palette applied in `lib/app.dart`; web `theme_color` / `background_color`
      updated; `theme-color` meta added.
- [ ] Dark scheme reviewed for contrast (or explicitly out of scope).
- [ ] Store and social artwork exported and linked from the README.
- [ ] Any bundled font licensed and listed in `THIRD_PARTY_NOTICES.md`.
- [ ] This file updated to describe what shipped, not what is missing.
