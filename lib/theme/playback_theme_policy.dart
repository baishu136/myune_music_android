/// The default playback surface inherits the app's current light/dark theme.
/// Only image-backed playback modes opt into the dedicated dark treatment.
bool shouldForceDarkPlaybackTheme({
  required bool customBackgroundActive,
  required bool followAlbumArtEnabled,
}) => customBackgroundActive || followAlbumArtEnabled;
