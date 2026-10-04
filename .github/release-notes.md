Paste links, get videos. Haul is a calm front-end for yt-dlp: share or paste one link, a hundred, or a whole channel, and it downloads them in parallel.

## Fixed in 0.1.1

On Android, 0.1.0 showed a "Set up Haul" screen with the error **r8**, and neither button worked. The release build's code shrinker (R8) had renamed part of the library that unpacks Haul's built-in Python and yt-dlp on first launch, so the engine never started. Shrinking is now off, the engine starts normally, and if it ever fails again you get a clear error screen with **Try again** and **Copy details**.

**Updating from 0.1.0 on Android:** uninstall 0.1.0 first, then install this APK. Each build is signed with a different key, so Android won't install over it. You won't lose anything, because 0.1.0 couldn't download.

## Download

| You have | Get this file |
| --- | --- |
| Android phone (almost all) | `Haul-android-arm64-v8a.apk` |
| Older 32-bit Android phone | `Haul-android-armeabi-v7a.apk` |
| Android emulator / Chromebook | `Haul-android-x86_64.apk` |
| Mac | `Haul-macos.zip` |
| Windows | `Haul-windows-x64.zip` |
| Linux | `Haul-linux-x64.tar.gz` |
| iPhone / iPad | `Haul-ios-unsigned.ipa` |

**Android:** open the APK and allow installing from your browser or file manager when asked. Then use **Share → Haul** from YouTube, Instagram, TikTok and other apps.

**Mac:** unzip, then right-click `Haul.app` → **Open** the first time (the app isn't notarized yet).

**Windows:** unzip and run `haul.exe`. **Linux:** unpack and run `bundle/haul`.

**iPhone / iPad:** sideload the `.ipa` with AltStore or Sideloadly. iOS doesn't let apps run yt-dlp themselves, so the iPhone app sends downloads to Haul on your computer and copies the videos back:

1. On your computer, open Haul → Settings → **Allow phone connections**.
2. On the phone, enter the address and the 6-letter code it shows.

Without installing anything, any phone browser on the same Wi-Fi can also open that address.

## In this release

- Paste one link or many; playlists and channels expand into their videos (with Undo).
- Parallel downloads with pause, resume and retry; partial files survive restarts.
- Quality presets (Best to 480p, MP3, M4A) or exact formats per video.
- Android: share-sheet intake, background downloads with a quiet notification, files in `Download/Haul`.
- Desktop: one-time setup of yt-dlp, ffmpeg and a JS runtime; drag and drop link files; copied-link suggestions.
- Remote mode for iPhone and any browser, protected by a pairing code.
- Accessible by default: WCAG AA contrast, 48dp touch targets, keyboard navigation, 200% text and reduced motion. See `docs/DESIGN.md`.

Only download what you have the right to keep.
