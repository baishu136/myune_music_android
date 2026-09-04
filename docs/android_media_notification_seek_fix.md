# Android notification seek compatibility fix

## Symptom

On Xiaomi HyperOS 1.0.1.0, dragging the system media-card progress bar could
stutter and then make the bar disappear. The elapsed and duration labels could
also overlap. The issue was reproducible while playback itself continued.

## Root cause

The Android Media3 adapter historically published a synthetic three-item
timeline: `[previous placeholder, current track, next placeholder]`. The
placeholder items intentionally had no duration and were non-seekable.

Some OEM controllers submit an absolute seek against media-item index `0`.
`SimpleBasePlayer` creates an optimistic state for that index after the seek
handler returns. When index `0` is the previous placeholder, SystemUI briefly
sees an unknown-duration, non-seekable current item and removes its seek bar.
An immediate state republish inside the handler cannot correct this because it
occurs before Media3 publishes the optimistic state.

## Fix

- Android publishes one stable, fully-described current item by default.
- Previous/next remain available through the existing Media3 player commands.
- The authoritative scrub state is republished on the next main-loop turn,
  after Media3 has installed its optimistic seek state.
- Scanner-derived duration remains available as a stable metadata override.
- The debug probe reports timeline mode, size, and current index.

## Hidden legacy rollback

The old synthetic timeline is retained for emergency compatibility builds and
is not exposed in user settings. Build with:

```text
flutter build apk --release --target-platform android-arm64 \
  --dart-define=MYUNE_LEGACY_ANDROID_MEDIA_TIMELINE=true
```

The normal build omits this flag and uses the corrected single-item timeline.
The rollback switch changes only Android's system media-session timeline; it
does not alter playback queues, application settings, or media files.

