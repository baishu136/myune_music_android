import '../page/setting/settings_provider.dart';

/// Background and pigment are independent. Turning off home theme colour must
/// never change image selection, blur/dim strengths, or saved theme settings.
({bool customImage, bool albumCover, bool hasBackground}) homeBackgroundPolicy(
  SettingsProvider settings, {
  required bool hasSong,
}) {
  final customImage =
      settings.homeThemeImageEnabled &&
      settings.homeThemeImagePath != null &&
      settings.homeThemeImagePath!.isNotEmpty;
  final albumCover = settings.followAlbumArtOnHome && hasSong;
  return (
    customImage: customImage,
    albumCover: albumCover,
    hasBackground: customImage || albumCover,
  );
}
