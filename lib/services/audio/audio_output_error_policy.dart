import 'package:mpv_audio_kit/mpv_audio_kit.dart';

// mpv owns the first reconnect attempt. A disconnect is not a failed song.
bool isRecoveringAudioDisconnect(MpvPlayerError error) =>
    error is MpvLogError &&
    error.prefix == 'ao/aaudio' &&
    error.text.contains('AAUDIO_ERROR_DISCONNECTED, trying to reload');

bool isAudioOutputFailure(MpvPlayerError error) =>
    isRecoveringAudioDisconnect(error) ||
    (error is MpvLogError &&
        ((error.prefix.startsWith('ao/') &&
                (error.text.contains('openStream() returned') ||
                    error.text.contains('requestStart() returned') ||
                    error.text.contains('Failed to create AudioTrack'))) ||
            error.text.contains('Could not open/initialize audio device')));
