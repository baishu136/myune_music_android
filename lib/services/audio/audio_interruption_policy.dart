import 'package:mpv_audio_kit/mpv_audio_kit.dart';

/// Maps the user-facing audio occupation preference to the media-session
/// policy used by Android Audio Focus and Apple audio interruptions.
InterruptionPolicy audioInterruptionPolicy({required bool autoPause}) {
  return autoPause
      ? InterruptionPolicy.pauseOnly
      : InterruptionPolicy.keepPlaying;
}
