import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../page/playlist/playlist_content_notifier.dart';
import '../page/playlist/playlist_models.dart';
import '../page/lyric_copy_page.dart';
import '../page/pages/statistics_page.dart';
import '../page/pages/audio_analysis_page.dart';
import '../page/setting/setting_page.dart';
import '../page/setting/settings_provider.dart';
import '../page/setting/tabs/info_icon.dart';
import '../page/statistics_page/statistics_manager.dart';
import '../widgets/playing_queue_drawer.dart';
import '../widgets/mobile_lyrics_list.dart';
import '../widgets/now_playing_cover_hero.dart';
import '../widgets/play_pause_button.dart';
import '../widgets/playback_progress_header.dart';
import '../widgets/sort_dialog.dart';
import '../widgets/transparent_chip_surface.dart';
import '../services/notification_service.dart';
import '../services/desktop_lyrics_controller.dart';
import '../services/song_group_presentation.dart';
import '../services/audio_cover_editor_service.dart';
import '../services/cover_override_service.dart';
import '../services/artwork_prefetch_plan.dart';
import '../services/interaction_performance_controller.dart';
import '../theme/theme_provider.dart';
import '../theme/playback_theme_policy.dart';
import '../widgets/custom_theme_background.dart';
import '../widgets/custom_theme_image_editor.dart';
import '../widgets/artwork_image.dart';

bool _hasCustomPlaybackTheme(SettingsProvider settings) {
  final path = settings.playbackThemeImagePath;
  return settings.playbackThemeImageEnabled && path != null && path.isNotEmpty;
}

bool _hasUsableAlbumArt(Song? song) =>
    song?.albumArt != null && song!.albumArt!.isNotEmpty;

bool _hasResolvedPlaybackTheme(
  SettingsProvider settings,
  PlaylistContentNotifier notifier,
) {
  final song = notifier.currentSong;
  final cachedArtwork = song == null
      ? null
      : notifier.coverForSongPath(song.filePath);
  return _hasCustomPlaybackTheme(settings) ||
      (settings.followAlbumArtOnPlayback &&
          (_hasUsableAlbumArt(song) ||
              (cachedArtwork != null && cachedArtwork.isNotEmpty)));
}

enum _CoverApplyTarget { appOnly, sourceFile }

Future<Uint8List?> _pickAndCropCover(BuildContext context) async {
  String? path;
  try {
    if (Platform.isAndroid) {
      path = await AudioCoverEditorService.pickImageFromGallery();
    } else {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: '选择封面图片',
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      );
      path = result?.files.single.path;
    }
  } catch (error) {
    if (context.mounted) {
      context.read<NotificationService>().error(
        '打开系统相册失败：${_coverWriteError(error)}',
      );
    }
    return null;
  }
  if (path == null || !context.mounted) return null;
  return showCustomThemeImageEditor(
    context,
    sourcePath: path,
    square: true,
    title: '裁剪封面',
  );
}

Future<_CoverApplyTarget?> _chooseCoverApplyTarget(
  BuildContext context, {
  required bool group,
}) => showModalBottomSheet<_CoverApplyTarget>(
  context: context,
  showDragHandle: true,
  builder: (sheetContext) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(Icons.layers_outlined),
          title: const Text('在播放器内更换'),
          subtitle: const Text('不修改音频文件，可随时重置'),
          onTap: () => Navigator.pop(sheetContext, _CoverApplyTarget.appOnly),
        ),
        ListTile(
          leading: const Icon(Icons.edit_note_outlined),
          title: Text(group ? '替换组内歌曲文件封面' : '替换文件封面'),
          subtitle: Text(group ? '写入该歌手/专辑内所有可写音频文件' : '直接写入当前音频文件的标签'),
          onTap: () =>
              Navigator.pop(sheetContext, _CoverApplyTarget.sourceFile),
        ),
        const SizedBox(height: 8),
      ],
    ),
  ),
);

Future<bool> _confirmSourceCoverWrite(
  BuildContext context, {
  required int count,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('替换文件封面？'),
        content: Text(
          count == 1
              ? '此操作会修改音频文件本身。写入过程会先创建临时副本，失败时保留原文件。'
              : '此操作会修改 $count 个音频文件本身。只会处理可写文件，失败的文件将保留原样。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('继续'),
          ),
        ],
      ),
    ) ??
    false;

Future<void> _downloadCover(
  BuildContext context,
  Uint8List bytes,
  String name,
) async {
  final safeName = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  try {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: '保存封面',
      fileName: '${safeName.isEmpty ? 'cover' : safeName}_cover.png',
      type: FileType.custom,
      allowedExtensions: const ['png'],
      bytes: bytes,
    );
    if (result != null && context.mounted) {
      context.read<NotificationService>().success('封面已保存');
    }
  } catch (error) {
    if (context.mounted) {
      context.read<NotificationService>().error('保存封面失败：$error');
    }
  }
}

String _coverWriteError(Object error) {
  if (error is PlatformException) {
    return error.message ?? error.code;
  }
  return error.toString();
}

/// Touch-first Android presentation. The desktop pages and their data model stay
/// intact; this shell only changes navigation density and common actions.
class MobileShell extends StatefulWidget {
  const MobileShell({super.key});

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  static const _notificationPromptedKey = 'notification_permission_prompted';
  static const _overlayPromptedKey = 'overlay_permission_prompted';
  int _tab = 0;
  late final PageController _homePageController;
  int? _programmaticTabTarget;
  int _homeNavigationRevision = 0;
  String _query = '';
  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<String>? _infoSubscription;
  bool _noticeStreamsBound = false;
  bool _animateLibraryEntrance = true;
  bool _librarySelectionMode = false;
  bool _isExiting = false;
  final Set<String> _selectedLibrarySongPaths = {};
  String? _pendingPlaylistName;
  String? _pendingPlaylistId;
  String _settingsSectionTitle = '个性化';

  static const _titles = ['音乐库', '歌单', '歌手', '专辑', '设置'];

  @override
  void initState() {
    super.initState();
    _homePageController = PageController();
    _homePageController.addListener(_markHomePageTransition);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_requestFirstLaunchPermissions());
    });
  }

  void _markHomePageTransition() {
    InteractionPerformanceController.instance.pulse(
      InteractionPhase.transition,
      settleAfter: const Duration(milliseconds: 140),
    );
  }

  Future<void> _requestFirstLaunchPermissions() async {
    await _requestNotificationPermissionOnFirstLaunch();
    if (!mounted) return;
    await _requestOverlayPermissionOnFirstLaunch();
  }

  Future<void> _requestNotificationPermissionOnFirstLaunch() async {
    if (!Platform.isAndroid) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_notificationPromptedKey) ?? false) return;
    await prefs.setBool(_notificationPromptedKey, true);
    final status = await Permission.notification.request();
    if (!mounted || status.isGranted) return;
    context.read<NotificationService>().warning('未授予通知权限，后台播放时可能无法显示播放器控制栏');
  }

  Future<void> _requestOverlayPermissionOnFirstLaunch() async {
    if (!Platform.isAndroid) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_overlayPromptedKey) ?? false) return;
    if (!mounted) return;

    final desktopLyrics = context.read<DesktopLyricsController>();
    if (await desktopLyrics.hasOverlayPermission()) {
      await prefs.setBool(_overlayPromptedKey, true);
      return;
    }
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('允许悬浮窗权限'),
        content: const Text('桌面歌词需要“显示在其他应用上层”权限。授权后仍需在设置中手动开启桌面歌词。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('暂不允许'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('前往授权'),
          ),
        ],
      ),
    );
    await prefs.setBool(_overlayPromptedKey, true);
    if (accepted == true) {
      await desktopLyrics.requestOverlayPermissionOnly();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_noticeStreamsBound) return;
    _noticeStreamsBound = true;
    final notifier = context.read<PlaylistContentNotifier>();
    final notices = context.read<NotificationService>();
    _errorSubscription = notifier.errorStream.listen(notices.error);
    _infoSubscription = notifier.infoStream.listen(notices.info);
  }

  @override
  void dispose() {
    _homeNavigationRevision++;
    _homePageController.dispose();
    _errorSubscription?.cancel();
    _infoSubscription?.cancel();
    super.dispose();
  }

  Future<void> _requestAudioAccess() async {
    final status = await Permission.audio.request();
    if (!status.isGranted) {
      if (!mounted) return;
      context.read<NotificationService>().warning('请允许“音乐和音频”权限后再导入歌曲');
    }
  }

  Future<void> _exitAndroidApp() async {
    if (_isExiting) return;
    _isExiting = true;
    final notifier = context.read<PlaylistContentNotifier>();
    try {
      await notifier.shutdownForAppExit();
    } catch (error, stackTrace) {
      debugPrint('Failed to shut down playback before exit: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    await SystemNavigator.pop();
  }

  Widget _buildHomePage(int index, bool useHomeTheme) {
    return switch (index) {
      0 => _LibraryTab(
        query: _query,
        animateEntrance: _animateLibraryEntrance,
        topEdgeFadeEnabled: useHomeTheme,
        onEntranceFinished: () => _animateLibraryEntrance = false,
        selectionMode: _librarySelectionMode,
        selectedPaths: _selectedLibrarySongPaths,
        onToggleSelection: _toggleLibrarySongSelection,
      ),
      1 => _PlaylistsTab(
        topEdgeFadeEnabled: useHomeTheme,
        onCreateFromLibrary: _startPlaylistSelection,
        onAddFromLibrary: _startExistingPlaylistSelection,
        onImportSongs: _showImportOptions,
      ),
      2 => _GroupTab(kind: '歌手', useHomeTheme: useHomeTheme),
      3 => _GroupTab(kind: '专辑', useHomeTheme: useHomeTheme),
      _ => _SettingsTab(
        onSwipeBack: () => _selectTab(3),
        onSectionChanged: (title) {
          if (_settingsSectionTitle == title) return;
          setState(() => _settingsSectionTitle = title);
        },
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final currentSong = context.select<PlaylistContentNotifier, Song?>(
      (notifier) => notifier.currentSong,
    );
    final notifier = context.read<PlaylistContentNotifier>();
    final homeCoverListenable = currentSong == null
        ? null
        : notifier.coverListenableForSongPath(currentSong.normalizedPath);
    final playlistSelection = context
        .select<PlaylistContentNotifier, ({bool enabled, int count})>(
          (value) => (
            enabled: value.isMultiSelectMode,
            count: value.selectedSongPaths.length,
          ),
        );
    final settings = context.watch<SettingsProvider>();
    final sortEnabled = switch (_tab) {
      0 => settings.libraryViewMode == LibraryViewMode.list,
      1 => settings.playlistViewMode == PlaylistViewMode.cards,
      2 => settings.artistGroupViewMode == GroupViewMode.list,
      3 => settings.albumGroupViewMode == GroupViewMode.list,
      _ => false,
    };
    final librarySelecting = _tab == 0 && _librarySelectionMode;
    final playlistSelecting = _tab == 1 && playlistSelection.enabled;
    final selecting = librarySelecting || playlistSelecting;
    final screen = MediaQuery.sizeOf(context);
    final isTablet = screen.shortestSide >= 600;
    final useCustomHomeTheme =
        settings.homeThemeImageEnabled &&
        settings.homeThemeImagePath != null &&
        settings.homeThemeImagePath!.isNotEmpty;
    // Keep the shell styling stable while artwork resolves. Only the background
    // below listens for cover changes, so song grids are not rebuilt into
    // temporary placeholders when the current thumbnail becomes available.
    final useHomeTheme =
        useCustomHomeTheme ||
        (settings.followAlbumArtOnHome && currentSong != null);
    final page = PageView.builder(
      controller: _homePageController,
      physics: selecting
          ? const NeverScrollableScrollPhysics()
          : const PageScrollPhysics(parent: BouncingScrollPhysics()),
      onPageChanged: _handleHomePageChanged,
      itemCount: _titles.length,
      itemBuilder: (context, index) => _KeepAlivePage(
        key: ValueKey('home-page-$index'),
        child: _buildHomePage(index, useHomeTheme),
      ),
    );
    final headerTitle = selecting
        ? '已选择 ${librarySelecting ? _selectedLibrarySongPaths.length : playlistSelection.count} 首'
        : _tab == 4
        ? _settingsSectionTitle
        : _titles[_tab];
    final headerTransitionKey = selecting
        ? 'selection'
        : 'title-$_tab-$headerTitle';
    final actionsTransitionKey = selecting
        ? 'selection-actions'
        : 'default-actions-$_tab';
    final scaffold = Scaffold(
      backgroundColor: useHomeTheme ? Colors.transparent : null,
      appBar: AppBar(
        backgroundColor: useHomeTheme ? Colors.transparent : null,
        scrolledUnderElevation: useHomeTheme ? 0 : null,
        leading: selecting
            ? IconButton(
                tooltip: '退出多选',
                icon: const Icon(Icons.close),
                onPressed: librarySelecting
                    ? _exitLibrarySelection
                    : notifier.exitMultiSelectMode,
              )
            : null,
        title: ClipRect(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 380),
            reverseDuration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (currentChild, previousChildren) => Stack(
              alignment: Alignment.centerLeft,
              children: [
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            ),
            transitionBuilder: (child, animation) {
              final isIncoming =
                  child.key == ValueKey<String>(headerTransitionKey);
              final slideAnimation = Tween<Offset>(
                begin: isIncoming
                    ? const Offset(1.1, 0)
                    : const Offset(-1.1, 0),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: slideAnimation, child: child),
              );
            },
            child: Text(
              headerTitle,
              key: ValueKey<String>(headerTransitionKey),
            ),
          ),
        ),
        actions: [
          ClipRect(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 380),
              reverseDuration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (currentChild, previousChildren) => Stack(
                alignment: Alignment.centerRight,
                children: [
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              ),
              transitionBuilder: (child, animation) {
                final isIncoming =
                    child.key == ValueKey<String>(actionsTransitionKey);
                final slideAnimation = Tween<Offset>(
                  begin: isIncoming
                      ? const Offset(1.1, 0)
                      : const Offset(-1.1, 0),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: slideAnimation,
                    child: child,
                  ),
                );
              },
              child: selecting
                  ? Row(
                      key: ValueKey<String>(actionsTransitionKey),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '全选',
                          icon: const Icon(Icons.select_all),
                          onPressed: librarySelecting
                              ? _selectAllLibrarySongs
                              : notifier.selectAllSongs,
                        ),
                        if (librarySelecting &&
                            (_pendingPlaylistName != null ||
                                _pendingPlaylistId != null))
                          IconButton(
                            tooltip: _pendingPlaylistId == null
                                ? '创建歌单'
                                : '添加到歌单',
                            icon: const Icon(Icons.playlist_add_check),
                            onPressed: _finishPlaylistSelection,
                          )
                        else if (librarySelecting) ...[
                          IconButton(
                            tooltip: '移除歌曲',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: _removeSelectedLibrarySongs,
                          ),
                          IconButton(
                            tooltip: '收藏',
                            icon: const Icon(Icons.favorite_border),
                            onPressed: _favoriteSelectedLibrarySongs,
                          ),
                        ] else
                          IconButton(
                            tooltip: '从当前歌单移除',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: playlistSelection.count == 0
                                ? null
                                : notifier.removeSelectedSongs,
                          ),
                      ],
                    )
                  : Row(
                      key: ValueKey<String>(actionsTransitionKey),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_tab < 4)
                          IconButton(
                            tooltip: sortEnabled ? '排序当前页面' : '当前查看方式使用固定排序',
                            icon: const Icon(Icons.sort),
                            onPressed: sortEnabled ? _showSortDialog : null,
                          ),
                        if (_tab == 0 || _tab == 1)
                          IconButton(
                            tooltip: '切换查看方式',
                            icon: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              child: Icon(
                                _tab == 0
                                    ? settings.libraryViewMode ==
                                              LibraryViewMode.indexed
                                          ? Icons.sort_by_alpha
                                          : Icons.view_list_outlined
                                    : settings.playlistViewMode ==
                                          PlaylistViewMode.split
                                    ? Icons.view_sidebar_outlined
                                    : Icons.view_carousel_outlined,
                                key: ValueKey(
                                  _tab == 0
                                      ? settings.libraryViewMode
                                      : settings.playlistViewMode,
                                ),
                              ),
                            ),
                            onPressed: _togglePrimaryViewMode,
                          ),
                        if (_tab == 2 || _tab == 3)
                          IconButton(
                            tooltip:
                                (_tab == 2
                                        ? settings.artistGroupViewMode
                                        : settings.albumGroupViewMode) ==
                                    GroupViewMode.list
                                ? '切换到字母分组'
                                : '切换到列表',
                            icon: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              child: Icon(
                                (_tab == 2
                                            ? settings.artistGroupViewMode
                                            : settings.albumGroupViewMode) ==
                                        GroupViewMode.list
                                    ? Icons.view_list_outlined
                                    : Icons.sort_by_alpha,
                                key: ValueKey(
                                  _tab == 2
                                      ? settings.artistGroupViewMode
                                      : settings.albumGroupViewMode,
                                ),
                              ),
                            ),
                            onPressed: _toggleGroupViewMode,
                          ),
                        if (_tab != 4)
                          IconButton(
                            tooltip: '搜索',
                            icon: const Icon(Icons.search),
                            onPressed: () => _showSearch(context),
                          ),
                        if (_tab == 4)
                          IconButton(
                            tooltip: '播放统计',
                            icon: const Icon(Icons.leaderboard_outlined),
                            onPressed: () => Navigator.of(context).push(
                              CupertinoPageRoute<void>(
                                builder: (_) => const StatisticsPage(),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
      body: isTablet
          ? Row(
              children: [
                SafeArea(
                  top: false,
                  right: false,
                  child: NavigationRail(
                    backgroundColor: useHomeTheme
                        ? Theme.of(
                            context,
                          ).colorScheme.surface.withValues(alpha: 0.78)
                        : null,
                    selectedIndex: _tab,
                    onDestinationSelected: _selectTab,
                    extended: screen.width >= 1100,
                    labelType: screen.width >= 1100
                        ? NavigationRailLabelType.none
                        : NavigationRailLabelType.selected,
                    groupAlignment: -0.75,
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.library_music_outlined),
                        selectedIcon: Icon(Icons.library_music),
                        label: Text('音乐库'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.playlist_play_outlined),
                        selectedIcon: Icon(Icons.playlist_play),
                        label: Text('歌单'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.person_outline),
                        selectedIcon: Icon(Icons.person),
                        label: Text('歌手'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.album_outlined),
                        selectedIcon: Icon(Icons.album),
                        label: Text('专辑'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.settings_outlined),
                        selectedIcon: Icon(Icons.settings),
                        label: Text('设置'),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: SafeArea(
                    top: false,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1200),
                        child: Column(
                          children: [
                            Expanded(child: page),
                            _MiniPlayer(translucent: useHomeTheme),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : page,
      floatingActionButton:
          _tab == 1 && settings.playlistViewMode != PlaylistViewMode.split
          ? FloatingActionButton.extended(
              onPressed: _showImportOptions,
              icon: const Icon(Icons.add),
              label: const Text('添加歌曲'),
            )
          : null,
      bottomNavigationBar: isTablet
          ? null
          : SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MiniPlayer(translucent: useHomeTheme),
                  NavigationBar(
                    backgroundColor: useHomeTheme
                        ? Theme.of(
                            context,
                          ).colorScheme.surface.withValues(alpha: 0.78)
                        : null,
                    selectedIndex: _tab,
                    onDestinationSelected: _selectTab,
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.library_music_outlined),
                        selectedIcon: Icon(Icons.library_music),
                        label: '音乐库',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.playlist_play_outlined),
                        selectedIcon: Icon(Icons.playlist_play),
                        label: '歌单',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.person_outline),
                        selectedIcon: Icon(Icons.person),
                        label: '歌手',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.album_outlined),
                        selectedIcon: Icon(Icons.album),
                        label: '专辑',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.settings_outlined),
                        selectedIcon: Icon(Icons.settings),
                        label: '设置',
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
    Widget buildHomeBackground(Widget child) {
      final currentAlbumArt = currentSong == null
          ? null
          : notifier.displayCoverForSong(currentSong);
      return CustomThemeBackground(
        path: settings.homeThemeImagePath,
        enabled: useCustomHomeTheme,
        dim: settings.homeThemeImageDim,
        blurSigma: settings.homeThemeImageBlur,
        coverBytes: currentAlbumArt,
        coverEnabled: settings.followAlbumArtOnHome && currentAlbumArt != null,
        coverDim: settings.homeAlbumArtBackgroundDim,
        coverBlurSigma: settings.homeAlbumArtBackgroundBlur,
        child: child,
      );
    }

    final background = homeCoverListenable == null
        ? buildHomeBackground(scaffold)
        : AnimatedBuilder(
            animation: homeCoverListenable,
            child: scaffold,
            builder: (context, child) => buildHomeBackground(child!),
          );
    return _PlaybackArtworkPreparationCoordinator(
      child: PopScope<void>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) unawaited(_exitAndroidApp());
        },
        child: RepaintBoundary(child: background),
      ),
    );
  }

  void _selectTab(int index) {
    if (index == _tab) return;
    if (index != 1) {
      context.read<PlaylistContentNotifier>().exitMultiSelectMode();
    }
    setState(() {
      if (index != 0) {
        _librarySelectionMode = false;
        _selectedLibrarySongPaths.clear();
        _pendingPlaylistName = null;
        _pendingPlaylistId = null;
      }
      _tab = index;
    });
    _animateHomePageTo(index);
  }

  void _handleHomePageChanged(int index) {
    final target = _programmaticTabTarget;
    if (target != null) {
      if (index != target) return;
      _programmaticTabTarget = null;
    }
    _homeNavigationRevision++;
    if (_tab == index) return;
    if (index != 1) {
      context.read<PlaylistContentNotifier>().exitMultiSelectMode();
    }
    setState(() {
      if (index != 0) {
        _librarySelectionMode = false;
        _selectedLibrarySongPaths.clear();
        _pendingPlaylistName = null;
        _pendingPlaylistId = null;
      }
      _tab = index;
    });
  }

  void _toggleLibrarySongSelection(Song song) {
    setState(() {
      _librarySelectionMode = true;
      final path = song.normalizedPath.toLowerCase();
      if (!_selectedLibrarySongPaths.add(path)) {
        _selectedLibrarySongPaths.remove(path);
      }
      if (_selectedLibrarySongPaths.isEmpty &&
          _pendingPlaylistName == null &&
          _pendingPlaylistId == null) {
        _librarySelectionMode = false;
      }
    });
  }

  void _exitLibrarySelection() {
    setState(() {
      _librarySelectionMode = false;
      _selectedLibrarySongPaths.clear();
      _pendingPlaylistName = null;
      _pendingPlaylistId = null;
    });
  }

  void _startPlaylistSelection(String playlistName) {
    setState(() {
      _pendingPlaylistName = playlistName.trim();
      _pendingPlaylistId = null;
      _selectedLibrarySongPaths.clear();
      _librarySelectionMode = true;
      _tab = 0;
    });
    _animateHomePageTo(0);
    context.read<NotificationService>().info('请从音乐库选择歌曲，完成后点击右上角创建');
  }

  void _startExistingPlaylistSelection(Playlist playlist) {
    setState(() {
      _pendingPlaylistName = null;
      _pendingPlaylistId = playlist.id;
      _selectedLibrarySongPaths.clear();
      _librarySelectionMode = true;
      _tab = 0;
    });
    _animateHomePageTo(0);
    context.read<NotificationService>().info(
      '请选择要添加到“${playlist.name}”的歌曲，完成后点击右上角',
    );
  }

  Future<void> _finishPlaylistSelection() async {
    final name = _pendingPlaylistName;
    final playlistId = _pendingPlaylistId;
    if (name == null && playlistId == null) return;
    if (_selectedLibrarySongPaths.isEmpty) {
      context.read<NotificationService>().warning('请至少选择一首歌曲');
      return;
    }
    final notifier = context.read<PlaylistContentNotifier>();
    final selected = notifier.allSongs
        .where(
          (song) => _selectedLibrarySongPaths.contains(
            song.normalizedPath.toLowerCase(),
          ),
        )
        .toList();
    if (playlistId != null) {
      final added = await notifier.addSongsToPlaylistById(
        playlistId,
        selected.map((song) => song.filePath).toList(),
      );
      if (!mounted) return;
      if (added == 0) {
        context.read<NotificationService>().info('所选歌曲均已存在于该歌单');
        return;
      }
      final targetIndex = notifier.playlists.indexWhere(
        (playlist) => playlist.id == playlistId,
      );
      if (targetIndex >= 0) notifier.setSelectedIndex(targetIndex);
    } else {
      final created = await notifier.saveQueueAsPlaylist(name!, selected);
      if (!mounted || !created) return;
    }
    setState(() {
      _pendingPlaylistName = null;
      _pendingPlaylistId = null;
      _selectedLibrarySongPaths.clear();
      _librarySelectionMode = false;
      _tab = 1;
    });
    _animateHomePageTo(1);
  }

  void _animateHomePageTo(int index) {
    if (!_homePageController.hasClients) {
      _programmaticTabTarget = null;
      return;
    }
    final navigationRevision = ++_homeNavigationRevision;
    _programmaticTabTarget = index;
    unawaited(_completeHomePageAnimation(index, navigationRevision));
  }

  Future<void> _completeHomePageAnimation(
    int target,
    int navigationRevision,
  ) async {
    try {
      await _homePageController
          .animateToPage(
            target,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
          )
          .timeout(const Duration(milliseconds: 700));
    } on TimeoutException {
      if (mounted &&
          navigationRevision == _homeNavigationRevision &&
          _homePageController.hasClients) {
        _homePageController.jumpToPage(target);
      }
    } catch (_) {
      // A newer navigation cancels the old scroll activity. Its revision owns
      // the final page state, so the superseded animation needs no recovery.
    }
    if (!mounted ||
        navigationRevision != _homeNavigationRevision ||
        _programmaticTabTarget != target) {
      return;
    }
    _programmaticTabTarget = null;
    final settledIndex = (_homePageController.page ?? target.toDouble())
        .round()
        .clamp(0, _titles.length - 1);
    if (_tab != settledIndex) {
      setState(() => _tab = settledIndex);
    }
  }

  void _selectAllLibrarySongs() {
    final songs = context.read<PlaylistContentNotifier>().allSongs;
    setState(() {
      _selectedLibrarySongPaths
        ..clear()
        ..addAll(songs.map((song) => song.normalizedPath.toLowerCase()));
    });
  }

  Future<void> _removeSelectedLibrarySongs() async {
    if (_selectedLibrarySongPaths.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('移除歌曲'),
        content: Text(
          '将从音乐库隐藏 ${_selectedLibrarySongPaths.length} 首歌曲。再次导入相同文件后会恢复显示。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final notifier = context.read<PlaylistContentNotifier>();
    final selectedSongs = notifier.allSongs
        .where(
          (song) => _selectedLibrarySongPaths.contains(
            song.normalizedPath.toLowerCase(),
          ),
        )
        .toList();
    await notifier.hideSongsFromLibrary(selectedSongs);
    if (mounted) _exitLibrarySelection();
  }

  Future<void> _favoriteSelectedLibrarySongs() async {
    if (_selectedLibrarySongPaths.isEmpty) return;
    final notifier = context.read<PlaylistContentNotifier>();
    final selected = notifier.allSongs
        .where(
          (song) => _selectedLibrarySongPaths.contains(
            song.normalizedPath.toLowerCase(),
          ),
        )
        .toList();
    await notifier.addSongsToFavorites(selected);
    if (mounted) _exitLibrarySelection();
  }

  Future<void> _showSortDialog() async {
    if (_tab == 2 || _tab == 3) {
      await _showGroupSortDialog(artist: _tab == 2);
      return;
    }
    final notifier = context.read<PlaylistContentNotifier>();
    final hasSongs = _tab == 0
        ? notifier.allSongs.isNotEmpty
        : notifier.selectedIndex >= 0 &&
              notifier.currentPlaylistSongs.isNotEmpty;
    if (!hasSongs) {
      context.read<NotificationService>().warning('没有歌曲可以排序');
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) =>
          SortDialog(initialPreference: notifier.currentSortPreference),
    );
    if (!mounted || result == null) return;

    final criterion = result['criterion'] as SortCriterion;
    final descending = result['descending'] as bool;
    if (_tab == 0) {
      await notifier.sortAllSongs(criterion: criterion, descending: descending);
    } else if (_tab == 1) {
      await notifier.sortCurrentPlaylist(
        criterion: criterion,
        descending: descending,
      );
    }
    if (mounted) {
      context.read<NotificationService>().success('歌曲排序已应用');
    }
  }

  Future<void> _showGroupSortDialog({required bool artist}) async {
    final settings = context.read<SettingsProvider>();
    var mode = artist
        ? settings.artistGroupSortMode
        : settings.albumGroupSortMode;
    var descending = artist
        ? settings.artistGroupSortDescending
        : settings.albumGroupSortDescending;
    final result =
        await showDialog<({GroupCollectionSortMode mode, bool descending})>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Text('排序${artist ? '歌手' : '专辑'}'),
              content: RadioGroup<GroupCollectionSortMode>(
                groupValue: mode,
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() {
                    mode = value;
                    if (value != GroupCollectionSortMode.name) {
                      descending = true;
                    }
                  });
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const RadioListTile<GroupCollectionSortMode>(
                      title: Text('按名称'),
                      value: GroupCollectionSortMode.name,
                    ),
                    const RadioListTile<GroupCollectionSortMode>(
                      title: Text('按歌曲数量'),
                      value: GroupCollectionSortMode.songCount,
                    ),
                    const RadioListTile<GroupCollectionSortMode>(
                      title: Text('按播放次数'),
                      value: GroupCollectionSortMode.playCount,
                    ),
                    const Divider(),
                    CheckboxListTile(
                      title: const Text('倒序排列'),
                      value: descending,
                      onChanged: (value) =>
                          setDialogState(() => descending = value ?? false),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, (
                    mode: mode,
                    descending: descending,
                  )),
                  child: const Text('应用排序'),
                ),
              ],
            ),
          ),
        );
    if (!mounted || result == null) return;
    if (artist) {
      await settings.setArtistGroupSort(
        mode: result.mode,
        descending: result.descending,
      );
    } else {
      await settings.setAlbumGroupSort(
        mode: result.mode,
        descending: result.descending,
      );
    }
  }

  Future<void> _showSearch(BuildContext context) async {
    final notifier = context.read<PlaylistContentNotifier>();
    if (_tab == 2 || _tab == 3) {
      final kind = _tab == 2 ? '歌手' : '专辑';
      final groups = kind == '歌手'
          ? notifier.songsByArtist
          : notifier.songsByAlbum;
      await showSearch<void>(
        context: context,
        delegate: _GroupSearchDelegate(kind: kind, groups: groups),
      );
      return;
    }
    final scope = _tab == 1
        ? _SongSearchScope.currentPlaylist
        : _SongSearchScope.library;
    final sourceSongs = List<Song>.from(
      scope == _SongSearchScope.currentPlaylist
          ? notifier.currentPlaylistSongs
          : notifier.allSongs,
    );
    await showSearch<void>(
      context: context,
      delegate: _SongSearchDelegate(
        initialQuery: _query,
        scope: scope,
        sourceSongs: sourceSongs,
        onChanged: (value) => setState(() => _query = value),
      ),
    );
    // 退出搜索后恢复原始曲库/歌单界面，搜索只负责定位歌曲。
    if (mounted && _query.isNotEmpty) {
      setState(() => _query = '');
    }
  }

  void _toggleGroupViewMode() {
    if (_tab != 2 && _tab != 3) return;
    final settings = context.read<SettingsProvider>();
    final current = _tab == 2
        ? settings.artistGroupViewMode
        : settings.albumGroupViewMode;
    final next = current == GroupViewMode.list
        ? GroupViewMode.indexedGrid
        : GroupViewMode.list;
    if (_tab == 2) {
      unawaited(settings.setArtistGroupViewMode(next));
    } else {
      unawaited(settings.setAlbumGroupViewMode(next));
    }
  }

  void _togglePrimaryViewMode() {
    final settings = context.read<SettingsProvider>();
    if (_tab == 0) {
      final next = settings.libraryViewMode == LibraryViewMode.list
          ? LibraryViewMode.indexed
          : LibraryViewMode.list;
      unawaited(settings.setLibraryViewMode(next));
      return;
    }
    if (_tab == 1) {
      final next = settings.playlistViewMode == PlaylistViewMode.cards
          ? PlaylistViewMode.split
          : PlaylistViewMode.cards;
      unawaited(settings.setPlaylistViewMode(next));
    }
  }

  Future<void> _showImportOptions() async {
    await _requestAudioAccess();
    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.audio_file_outlined),
              title: const Text('导入单曲'),
              subtitle: const Text('可一次选择一首或多首歌曲'),
              onTap: () => Navigator.pop(sheetContext, 'files'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_copy_outlined),
              title: const Text('导入整个文件夹'),
              subtitle: const Text('递归导入文件夹及子文件夹内的歌曲'),
              onTap: () => Navigator.pop(sheetContext, 'folder'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    final playlist = context.read<PlaylistContentNotifier>();
    if (action == 'folder') {
      await playlist.pickFolderAndAddSongs();
    } else {
      await playlist.pickAndAddSongs();
    }
  }
}

class _LibraryTab extends StatefulWidget {
  const _LibraryTab({
    required this.query,
    required this.animateEntrance,
    required this.topEdgeFadeEnabled,
    required this.onEntranceFinished,
    required this.selectionMode,
    required this.selectedPaths,
    required this.onToggleSelection,
  });
  final String query;
  final bool animateEntrance;
  final bool topEdgeFadeEnabled;
  final VoidCallback onEntranceFinished;
  final bool selectionMode;
  final Set<String> selectedPaths;
  final ValueChanged<Song> onToggleSelection;

  @override
  State<_LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<_LibraryTab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
    value: widget.animateEntrance ? 0 : 1,
  );
  bool _entranceStarted = false;

  Future<void> _playEntrance() async {
    try {
      await _entranceController.forward().timeout(
        const Duration(milliseconds: 1200),
      );
    } on TimeoutException {
      if (mounted) _entranceController.value = 1;
    } finally {
      if (mounted) widget.onEntranceFinished();
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final libraryState = context
        .select<PlaylistContentNotifier, ({int revision, bool loaded})>(
          (notifier) => (
            revision: notifier.libraryRevision,
            loaded: notifier.allSongsLoaded,
          ),
        );
    final notifier = context.read<PlaylistContentNotifier>();
    final libraryViewMode = context.select<SettingsProvider, LibraryViewMode>(
      (settings) => settings.libraryViewMode,
    );
    final songs = notifier.allSongs;
    final filtered = widget.query.isEmpty
        ? songs
        : notifier.searchSongs(widget.query, songs);
    if (widget.animateEntrance && songs.isNotEmpty && !_entranceStarted) {
      _entranceStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_playEntrance());
      });
    }
    if (!libraryState.loaded && songs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (songs.isEmpty) return const _EmptyLibrary();
    final displayedSongs = widget.query.isEmpty && !widget.selectionMode
        ? notifier.pinnedFirst(
            PlaylistContentNotifier.libraryPinScope,
            filtered,
          )
        : filtered;
    return _TopEdgeFade(
      enabled: widget.topEdgeFadeEnabled,
      child: _SongList(
        songs: displayedSongs,
        pinScope: PlaylistContentNotifier.libraryPinScope,
        entranceAnimation: widget.animateEntrance ? _entranceController : null,
        selectionMode: widget.selectionMode,
        selectedPaths: widget.selectedPaths,
        onToggleSelection: widget.onToggleSelection,
        groupByInitial: libraryViewMode == LibraryViewMode.indexed,
        onPlay: (index) =>
            notifier.playAllSongsSearchResult(displayedSongs[index]),
      ),
    );
  }
}

class _PlaylistsTab extends StatelessWidget {
  const _PlaylistsTab({
    required this.topEdgeFadeEnabled,
    required this.onCreateFromLibrary,
    required this.onAddFromLibrary,
    required this.onImportSongs,
  });

  final bool topEdgeFadeEnabled;
  final ValueChanged<String> onCreateFromLibrary;
  final ValueChanged<Playlist> onAddFromLibrary;
  final Future<void> Function() onImportSongs;

  @override
  Widget build(BuildContext context) {
    final view = context
        .select<
          PlaylistContentNotifier,
          ({
            int revision,
            int selectedIndex,
            List<Song> songs,
            bool selecting,
            Set<String> selectedPaths,
          })
        >(
          (notifier) => (
            revision: notifier.playlistRevision,
            selectedIndex: notifier.selectedIndex,
            songs: notifier.currentPlaylistSongs,
            selecting: notifier.isMultiSelectMode,
            selectedPaths: notifier.selectedSongPaths,
          ),
        );
    final notifier = context.read<PlaylistContentNotifier>();
    final playlistViewMode = context.select<SettingsProvider, PlaylistViewMode>(
      (settings) => settings.playlistViewMode,
    );
    final hasSelection =
        view.selectedIndex >= 0 &&
        view.selectedIndex < notifier.playlists.length;
    final selectedPlaylist = hasSelection
        ? notifier.playlists[view.selectedIndex]
        : null;
    final pinScope = selectedPlaylist == null
        ? null
        : notifier.playlistPinScope(selectedPlaylist.id);
    final displayedSongs = pinScope == null
        ? view.songs
        : notifier.pinnedFirst(pinScope, view.songs);

    Widget buildCurrentSongs() => selectedPlaylist == null
        ? const Center(child: Text('选择一个歌单开始管理音乐'))
        : _SongList(
            songs: displayedSongs,
            pinScope: pinScope,
            onPlay: (index) =>
                notifier.playCurrentPlaylistSearchResult(displayedSongs[index]),
            showRemove: true,
            selectionMode: view.selecting,
            selectedPaths: view.selectedPaths
                .map((path) => path.toLowerCase())
                .toSet(),
            onToggleSelection: (song) {
              if (!notifier.isMultiSelectMode) {
                notifier.enterMultiSelectMode();
              }
              notifier.toggleSongSelection(song);
            },
          );

    if (playlistViewMode == PlaylistViewMode.split) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final railWidth = (constraints.maxWidth * .29)
              .clamp(124.0, 180.0)
              .toDouble();

          Widget railAction({
            required String label,
            required IconData icon,
            required VoidCallback onTap,
          }) => Expanded(
            child: Tooltip(
              message: label,
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onTap,
                  child: SizedBox(
                    height: 48,
                    child: Center(child: Icon(icon, size: 24)),
                  ),
                ),
              ),
            ),
          );

          return Row(
            children: [
              SizedBox(
                width: railWidth,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          railAction(
                            label: '新建歌单',
                            icon: Icons.add,
                            onTap: () => _newPlaylist(context),
                          ),
                          const SizedBox(width: 6),
                          railAction(
                            label: '导入文件',
                            icon: Icons.audio_file_outlined,
                            onTap: () {
                              if (selectedPlaylist == null) {
                                context.read<NotificationService>().warning(
                                  '请先选择一个歌单',
                                );
                                return;
                              }
                              unawaited(onImportSongs());
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.builder(
                          itemCount: notifier.playlists.length,
                          itemBuilder: (context, index) {
                            final playlist = notifier.playlists[index];
                            final selected = index == view.selectedIndex;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 7),
                              child: Material(
                                color: selected
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.secondaryContainer
                                    : Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(12),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => notifier.setSelectedIndex(index),
                                  onLongPress: () => _showPlaylistActions(
                                    context,
                                    index: index,
                                    playlist: playlist,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 10,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          playlist.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${playlist.songFilePaths.length} 首',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.labelSmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: _TopEdgeFade(
                  enabled: topEdgeFadeEnabled,
                  child: buildCurrentSongs(),
                ),
              ),
            ],
          );
        },
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 94,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            itemCount: notifier.playlists.length + 1,
            itemBuilder: (context, index) {
              if (index == notifier.playlists.length) {
                return _PlaylistCard(
                  name: '新建歌单',
                  icon: Icons.add,
                  onTap: () => _newPlaylist(context),
                );
              }
              final playlist = notifier.playlists[index];
              return _PlaylistCard(
                name: playlist.name,
                selected: index == view.selectedIndex,
                subtitle: '${playlist.songFilePaths.length} 首',
                onTap: () => notifier.setSelectedIndex(index),
                onLongPress: () => _showPlaylistActions(
                  context,
                  index: index,
                  playlist: playlist,
                ),
              );
            },
          ),
        ),
        Expanded(
          child: _TopEdgeFade(
            enabled: topEdgeFadeEnabled,
            child: buildCurrentSongs(),
          ),
        ),
      ],
    );
  }

  Future<void> _showPlaylistActions(
    BuildContext context, {
    required int index,
    required Playlist playlist,
  }) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.vertical_align_top),
              title: const Text('置顶歌单'),
              subtitle: playlist.isDefault ? const Text('默认歌单已固定在顶部') : null,
              enabled: !playlist.isDefault,
              onTap: playlist.isDefault
                  ? null
                  : () => Navigator.pop(sheetContext, 'pin'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('重命名歌单'),
              subtitle: playlist.isDefault ? const Text('默认歌单不可重命名') : null,
              enabled: !playlist.isDefault,
              onTap: playlist.isDefault
                  ? null
                  : () => Navigator.pop(sheetContext, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.library_music_outlined),
              title: const Text('从音乐库添加歌曲'),
              subtitle: playlist.isFolderBased
                  ? const Text('文件夹歌单由所选文件夹自动维护')
                  : null,
              enabled: !playlist.isFolderBased,
              onTap: playlist.isFolderBased
                  ? null
                  : () => Navigator.pop(sheetContext, 'add_library'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('移除歌单'),
              subtitle: playlist.isDefault ? const Text('默认歌单不可移除') : null,
              enabled: !playlist.isDefault,
              onTap: playlist.isDefault
                  ? null
                  : () => Navigator.pop(sheetContext, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;

    final notifier = context.read<PlaylistContentNotifier>();
    if (action == 'pin') {
      await notifier.pinPlaylist(index);
      return;
    }
    if (action == 'rename') {
      await _renamePlaylist(context, index: index, currentName: playlist.name);
      return;
    }
    if (action == 'add_library') {
      onAddFromLibrary(playlist);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('移除歌单'),
        content: Text('确定移除歌单“${playlist.name}”吗？歌曲文件不会从设备中删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await notifier.deletePlaylist(index);
    }
  }

  Future<void> _renamePlaylist(
    BuildContext context, {
    required int index,
    required String currentName,
  }) async {
    final controller = TextEditingController(text: currentName);
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: currentName.length,
    );
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重命名歌单'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: '歌单名称',
            hintText: '输入新的歌单名称',
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || !context.mounted) return;
    context.read<PlaylistContentNotifier>().editPlaylistName(index, newName);
  }

  Future<void> _newPlaylist(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新建歌单'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '歌单名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty && context.mounted) {
      final type = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Wrap(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 4, 24, 8),
                child: Text(
                  '选择歌曲来源',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add),
                title: const Text('创建空歌单'),
                subtitle: const Text('创建后再导入单曲或文件夹'),
                onTap: () => Navigator.pop(sheetContext, 'empty'),
              ),
              ListTile(
                leading: const Icon(Icons.library_music_outlined),
                title: const Text('在乐库中选取'),
                subtitle: const Text('前往首页音乐库，多选已有歌曲组成歌单'),
                onTap: () => Navigator.pop(sheetContext, 'library'),
              ),
              ListTile(
                leading: const Icon(Icons.folder_copy_outlined),
                title: const Text('文件夹歌单'),
                subtitle: const Text('扫描并持续同步所选文件夹'),
                onTap: () => Navigator.pop(sheetContext, 'folder'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      if (!context.mounted || type == null) return;
      if (type == 'empty') {
        context.read<PlaylistContentNotifier>().addPlaylist(name);
        return;
      }
      if (type == 'library') {
        onCreateFromLibrary(name);
        return;
      }
      final path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择音乐文件夹',
      );
      if (path != null && context.mounted) {
        context.read<PlaylistContentNotifier>().addPlaylist(
          name,
          folderPaths: [path],
        );
      }
    }
  }
}

class _GroupTab extends StatelessWidget {
  const _GroupTab({required this.kind, required this.useHomeTheme});
  final String kind;
  final bool useHomeTheme;

  @override
  Widget build(BuildContext context) {
    context.select<PlaylistContentNotifier, int>(
      (notifier) => notifier.libraryRevision,
    );
    final notifier = context.read<PlaylistContentNotifier>();
    final groups = kind == '歌手'
        ? notifier.songsByArtist
        : notifier.songsByAlbum;
    if (groups.isEmpty) return const _EmptyLibrary();
    final settings = context.watch<SettingsProvider>();
    final coverOverrides = context.watch<CoverOverrideService>();
    final statistics = context.watch<StatisticsManager>();
    final playCounts = SongGroupPresentation.normalizedPlayCounts(
      statistics.statisticsData.songStats,
    );
    final viewMode = kind == '歌手'
        ? settings.artistGroupViewMode
        : settings.albumGroupViewMode;
    final sortMode = kind == '歌手'
        ? settings.artistGroupSortMode
        : settings.albumGroupSortMode;
    final sortDescending = kind == '歌手'
        ? settings.artistGroupSortDescending
        : settings.albumGroupSortDescending;
    final effectiveSortMode = viewMode == GroupViewMode.list
        ? sortMode
        : GroupCollectionSortMode.name;
    final effectiveDescending =
        viewMode == GroupViewMode.list && sortDescending;
    final groupPlayCounts =
        effectiveSortMode == GroupCollectionSortMode.playCount
        ? <String, int>{
            for (final entry in groups.entries)
              entry.key: entry.value.fold(
                0,
                (sum, song) =>
                    sum + SongGroupPresentation.playCount(song, playCounts),
              ),
          }
        : const <String, int>{};
    final sortedEntries = groups.entries.toList()
      ..sort((a, b) {
        final nameResult = SongGroupPresentation.alphabeticSortKey(
          a.key,
        ).compareTo(SongGroupPresentation.alphabeticSortKey(b.key));
        final primaryResult = switch (effectiveSortMode) {
          GroupCollectionSortMode.name => nameResult,
          GroupCollectionSortMode.songCount => a.value.length.compareTo(
            b.value.length,
          ),
          GroupCollectionSortMode.playCount =>
            (groupPlayCounts[a.key] ?? 0).compareTo(
              groupPlayCounts[b.key] ?? 0,
            ),
        };
        if (primaryResult != 0) {
          return effectiveDescending ? -primaryResult : primaryResult;
        }
        return nameResult;
      });
    final orderedNames = notifier.pinnedNamesFirst(
      kind == '歌手'
          ? PlaylistContentNotifier.artistsPinScope
          : PlaylistContentNotifier.albumsPinScope,
      sortedEntries.map((entry) => entry.key),
    );
    final entriesByName = {for (final entry in sortedEntries) entry.key: entry};
    final entries = orderedNames
        .map((name) => entriesByName[name]!)
        .toList(growable: false);
    final pinScope = kind == '歌手'
        ? PlaylistContentNotifier.artistsPinScope
        : PlaylistContentNotifier.albumsPinScope;
    final indexedPartition = viewMode == GroupViewMode.indexedGrid
        ? SongGroupPresentation.separatePinned(
            entries,
            (entry) => notifier.isPinned(pinScope, entry.key),
          )
        : (pinned: <MapEntry<String, List<Song>>>[], regular: entries);
    final pinnedEntries = indexedPartition.pinned;
    final regularEntries = indexedPartition.regular;
    final indexedSections = viewMode == GroupViewMode.indexedGrid
        ? SongGroupPresentation.groupByInitial(
            regularEntries,
            (entry) => entry.key,
          )
        : <String, List<MapEntry<String, List<Song>>>>{};
    final displayedEntries = viewMode == GroupViewMode.indexedGrid
        ? <MapEntry<String, List<Song>>>[
            ...pinnedEntries,
            ...indexedSections.values.expand((section) => section),
          ]
        : entries;
    final representativeSongs = displayedEntries
        .map((item) => _representativeSong(settings, item, playCounts))
        .whereType<Song>()
        .toList(growable: false);
    final scheme = Theme.of(context).colorScheme;
    Widget buildGridCard(
      MapEntry<String, List<Song>> item, {
      required bool showSongCount,
    }) {
      final isPinned = notifier.isPinned(pinScope, item.key);
      final artwork = _groupArtworkWidget(
        settings,
        coverOverrides,
        item,
        playCounts,
        highResolution: true,
        displaySize: showSongCount
            ? ArtworkSize.groupLarge
            : ArtworkSize.groupCompact,
      );
      return Card(
        elevation: 0,
        margin: showSongCount ? const EdgeInsets.all(4) : EdgeInsets.zero,
        color: scheme.surfaceContainerLow.withValues(
          alpha: useHomeTheme ? .62 : 1,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openCollection(context, item),
          onLongPress: () =>
              _showGroupActions(context, notifier, settings, item, playCounts),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    artwork,
                    if (isPinned)
                      const Positioned(
                        top: 8,
                        right: 8,
                        child: _GroupPinBadge(),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: showSongCount
                    ? const EdgeInsets.fromLTRB(10, 8, 10, 10)
                    : const EdgeInsets.fromLTRB(6, 5, 6, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: showSongCount
                          ? Theme.of(context).textTheme.titleMedium
                          : Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                    ),
                    if (showSongCount) ...[
                      const SizedBox(height: 3),
                      Text(
                        '${item.value.length} 首歌曲',
                        maxLines: 1,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget buildIndexedHeader(String label) => SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );

    Widget buildIndexedGrid(List<MapEntry<String, List<Song>>> items) =>
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 88,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: .76,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) =>
                  buildGridCard(items[index], showSongCount: false),
              childCount: items.length,
            ),
          ),
        );

    final collection = switch (viewMode) {
      GroupViewMode.indexedGrid => CustomScrollView(
        key: ValueKey('$kind-indexed-grid-view'),
        slivers: [
          if (pinnedEntries.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SizedBox(height: 10)),
            buildIndexedGrid(pinnedEntries),
          ],
          for (final section in indexedSections.entries) ...[
            buildIndexedHeader(section.key),
            buildIndexedGrid(section.value),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
      GroupViewMode.list => ListView.separated(
        key: ValueKey('$kind-list-view'),
        padding: const EdgeInsets.only(bottom: 20),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = entries[index];
          final isPinned = notifier.isPinned(pinScope, item.key);
          final artwork = _groupArtworkWidget(
            settings,
            coverOverrides,
            item,
            playCounts,
            highResolution: false,
          );
          return ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox.square(dimension: 52, child: artwork),
            ),
            title: Text(item.key),
            subtitle: Text('${item.value.length} 首歌曲'),
            trailing: isPinned
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.push_pin, size: 20),
                      SizedBox(width: 4),
                      Icon(Icons.chevron_right),
                    ],
                  )
                : const Icon(Icons.chevron_right),
            onTap: () => _openCollection(context, item),
            onLongPress: () => _showGroupActions(
              context,
              notifier,
              settings,
              item,
              playCounts,
            ),
          );
        },
      ),
    };
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              kind == '歌手'
                  ? '共 ${entries.length} 位歌手'
                  : '共 ${entries.length} 张专辑',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _ArtworkPrefetchViewport(
            songs: representativeSongs,
            itemExtent: switch (viewMode) {
              GroupViewMode.list => 68,
              GroupViewMode.indexedGrid => 112,
            },
            child: collection,
          ),
        ),
      ],
    );
  }

  void _openCollection(
    BuildContext context,
    MapEntry<String, List<Song>> item,
  ) {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => _SongCollectionPage(
          title: item.key,
          songs: item.value,
          pinScope: kind == '歌手'
              ? context.read<PlaylistContentNotifier>().artistSongsPinScope(
                  item.key,
                )
              : context.read<PlaylistContentNotifier>().albumSongsPinScope(
                  item.key,
                ),
        ),
      ),
    );
  }

  Future<void> _showGroupActions(
    BuildContext context,
    PlaylistContentNotifier notifier,
    SettingsProvider settings,
    MapEntry<String, List<Song>> item,
    Map<String, int> playCounts,
  ) async {
    final scope = kind == '歌手'
        ? PlaylistContentNotifier.artistsPinScope
        : PlaylistContentNotifier.albumsPinScope;
    final pinned = notifier.isPinned(scope, item.key);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(pinned ? Icons.push_pin_outlined : Icons.push_pin),
              title: Text(pinned ? '取消置顶' : '置顶'),
              onTap: () => Navigator.pop(sheetContext, 'pin'),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text('设置$kind封面'),
              onTap: () => Navigator.pop(sheetContext, 'cover'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    if (action == 'pin') {
      await notifier.togglePinned(scope, item.key);
    } else {
      await _showCoverPicker(context, notifier, settings, item, playCounts);
    }
  }

  Song? _representativeSong(
    SettingsProvider settings,
    MapEntry<String, List<Song>> item,
    Map<String, int> playCounts,
  ) {
    final overridePath = kind == '歌手'
        ? settings.artistGroupCoverPaths[item.key]
        : settings.albumGroupCoverPaths[item.key];
    if (overridePath != null) {
      for (final song in item.value) {
        if (song.normalizedPath.toLowerCase() == overridePath.toLowerCase()) {
          return song;
        }
      }
    }
    return SongGroupPresentation.representativeSong(item.value, playCounts);
  }

  Uint8List? _groupArtwork(
    PlaylistContentNotifier notifier,
    SettingsProvider settings,
    CoverOverrideService coverOverrides,
    MapEntry<String, List<Song>> item,
    Map<String, int> playCounts,
  ) {
    final override = coverOverrides.groupCover(
      artist: kind == '歌手',
      group: item.key,
    );
    if (override != null && override.isNotEmpty) return override;
    final song = _representativeSong(settings, item, playCounts);
    if (song == null) return null;
    return notifier.displayCoverForSong(song);
  }

  Widget _groupArtworkWidget(
    SettingsProvider settings,
    CoverOverrideService coverOverrides,
    MapEntry<String, List<Song>> item,
    Map<String, int> playCounts, {
    required bool highResolution,
    ArtworkSize displaySize = ArtworkSize.groupLarge,
  }) {
    final override = coverOverrides.groupCover(
      artist: kind == '歌手',
      group: item.key,
    );
    return _RequestedGroupArtwork(
      song: _representativeSong(settings, item, playCounts),
      overrideArtwork: override,
      fallbackIcon: kind == '歌手' ? Icons.person : Icons.album,
      highResolution: highResolution,
      displaySize: displaySize,
    );
  }

  Widget _groupArtworkView(BuildContext context, Uint8List? artwork) {
    if (artwork != null && artwork.isNotEmpty) {
      return ArtworkImage(
        bytes: artwork,
        size: ArtworkSize.medium,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHigh,
      child: Icon(
        kind == '歌手' ? Icons.person : Icons.album,
        size: 42,
        color: scheme.onSurfaceVariant,
      ),
    );
  }

  Future<void> _showCoverPicker(
    BuildContext context,
    PlaylistContentNotifier notifier,
    SettingsProvider settings,
    MapEntry<String, List<Song>> item,
    Map<String, int> playCounts,
  ) async {
    final coverOverrides = context.read<CoverOverrideService>();
    final sorted = SongGroupPresentation.sortByPlayCount(
      item.value,
      playCounts,
    );
    final currentArtwork = _groupArtwork(
      notifier,
      settings,
      coverOverrides,
      item,
      playCounts,
    );
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  '设置“${item.key}”封面',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.auto_awesome),
                title: const Text('自动选择'),
                subtitle: const Text('使用播放次数最多的歌曲封面'),
                onTap: () async {
                  await coverOverrides.setGroupCover(
                    artist: kind == '歌手',
                    group: item.key,
                  );
                  await settings.setGroupCoverPath(
                    artist: kind == '歌手',
                    group: item.key,
                  );
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('从相册选取并裁剪'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Future.microtask(() async {
                    if (!context.mounted) return;
                    final artwork = await _pickAndCropCover(context);
                    if (!context.mounted || artwork == null) return;
                    await _applyGroupCover(
                      context,
                      notifier,
                      settings,
                      coverOverrides,
                      item,
                      artwork,
                    );
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('下载当前封面'),
                enabled: currentArtwork != null && currentArtwork.isNotEmpty,
                onTap: currentArtwork == null || currentArtwork.isEmpty
                    ? null
                    : () {
                        Navigator.pop(sheetContext);
                        unawaited(
                          _downloadCover(context, currentArtwork, item.key),
                        );
                      },
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: sorted.length,
                  itemBuilder: (context, index) {
                    final song = sorted[index];
                    final artwork = notifier.displayCoverForSong(song);
                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox.square(
                          dimension: 44,
                          child: _groupArtworkView(context, artwork),
                        ),
                      ),
                      title: Text(song.title),
                      subtitle: Text(
                        '${SongGroupPresentation.playCount(song, playCounts)} 次播放',
                      ),
                      enabled: artwork != null && artwork.isNotEmpty,
                      onTap: artwork == null || artwork.isEmpty
                          ? null
                          : () {
                              Navigator.pop(sheetContext);
                              Future.microtask(() async {
                                if (!context.mounted) return;
                                await _applyGroupCover(
                                  context,
                                  notifier,
                                  settings,
                                  coverOverrides,
                                  item,
                                  artwork,
                                  sourceSongPath: song.normalizedPath,
                                );
                              });
                            },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _applyGroupCover(
    BuildContext context,
    PlaylistContentNotifier notifier,
    SettingsProvider settings,
    CoverOverrideService coverOverrides,
    MapEntry<String, List<Song>> item,
    Uint8List artwork, {
    String? sourceSongPath,
  }) async {
    final target = await _chooseCoverApplyTarget(context, group: true);
    if (!context.mounted || target == null) return;
    if (target == _CoverApplyTarget.appOnly) {
      if (sourceSongPath != null) {
        await coverOverrides.setGroupCover(
          artist: kind == '歌手',
          group: item.key,
        );
        await settings.setGroupCoverPath(
          artist: kind == '歌手',
          group: item.key,
          songPath: sourceSongPath,
        );
      } else {
        await settings.setGroupCoverPath(artist: kind == '歌手', group: item.key);
        await coverOverrides.setGroupCover(
          artist: kind == '歌手',
          group: item.key,
          bytes: artwork,
        );
      }
      if (context.mounted) {
        context.read<NotificationService>().success('$kind封面已更换');
      }
      return;
    }

    if (!await _confirmSourceCoverWrite(context, count: item.value.length) ||
        !context.mounted) {
      return;
    }
    var success = 0;
    var failed = 0;
    for (final song in item.value) {
      try {
        await AudioCoverEditorService.replaceEmbeddedCover(
          song.filePath,
          artwork,
        );
        await coverOverrides.setSongCover(song.filePath, null);
        await notifier.refreshSongCoverAfterFileEdit(song.filePath);
        success++;
      } catch (_) {
        failed++;
      }
    }
    if (!context.mounted) return;
    if (success == 0) {
      context.read<NotificationService>().error(
        '没有文件被修改，请检查文件格式、权限或 Android 版本',
      );
    } else if (failed > 0) {
      context.read<NotificationService>().warning(
        '已替换 $success 首，$failed 首失败并保留原文件',
      );
    } else {
      context.read<NotificationService>().success('已替换 $success 首歌曲的文件封面');
    }
  }
}

/// Gradually hides list content as it leaves the top of the viewport while
/// keeping the page background and header completely untouched.
class _TopEdgeFade extends StatefulWidget {
  const _TopEdgeFade({required this.child, required this.enabled});

  final Widget child;
  final bool enabled;
  static const double _fadeExtent = 56;

  @override
  State<_TopEdgeFade> createState() => _TopEdgeFadeState();
}

class _TopEdgeFadeState extends State<_TopEdgeFade>
    with SingleTickerProviderStateMixin {
  static const _fadeInDuration = Duration(milliseconds: 150);
  static const _scrollEpsilon = 0.25;

  late final AnimationController _controller;
  bool _userGestureActive = false;
  bool _hasUserScrolled = false;

  @override
  void initState() {
    super.initState();
    // The effect must never be visible as a side effect of initial layout,
    // restored scroll positions, or the first batch of data arriving.
    _controller = AnimationController(
      vsync: this,
      duration: _fadeInDuration,
      value: 0,
    );
  }

  @override
  void didUpdateWidget(covariant _TopEdgeFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) {
      _userGestureActive = false;
      _hasUserScrolled = false;
      _hideImmediately();
    }
    // Re-enabling intentionally leaves the effect hidden until the next
    // effective user scroll.
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;

    if (!widget.enabled) {
      _userGestureActive = false;
      _hasUserScrolled = false;
      return false;
    }

    if (notification is ScrollStartNotification) {
      _userGestureActive = notification.dragDetails != null;
      return false;
    }

    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      final isAwayFromTop =
          notification.metrics.pixels >
          notification.metrics.minScrollExtent + _scrollEpsilon;
      final hasActualMovement = delta.abs() > _scrollEpsilon;

      if (_userGestureActive && hasActualMovement) {
        _hasUserScrolled = true;
      }

      if (!isAwayFromTop) {
        _hideImmediately();
      } else if (_hasUserScrolled) {
        // Keep the mask active after scrolling stops. This also lets a fling
        // continue from the user's gesture without resetting the transition.
        _controller.forward();
      }
      return false;
    }

    if (notification is OverscrollNotification) {
      final isAtTop =
          notification.metrics.pixels <=
          notification.metrics.minScrollExtent + _scrollEpsilon;
      if (isAtTop) _hideImmediately();
      return false;
    }

    if (notification is ScrollEndNotification) {
      _userGestureActive = false;
    } else if (notification is UserScrollNotification &&
        notification.direction == ScrollDirection.idle) {
      _userGestureActive = false;
    }
    return false;
  }

  void _hideImmediately() {
    _controller.stop();
    _controller.value = 0;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          final opacity = Curves.fastOutSlowIn.transform(_controller.value);
          return ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) {
              final fadeStop = bounds.height <= 0
                  ? 0.0
                  : (_TopEdgeFade._fadeExtent / bounds.height)
                        .clamp(0.0, 1.0)
                        .toDouble();
              return LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.fromRGBO(0, 0, 0, 1 - opacity),
                  Colors.black,
                  Colors.black,
                ],
                stops: [0, fadeStop, 1],
              ).createShader(bounds);
            },
            child: child,
          );
        },
      ),
    );
  }
}

class _GroupPinBadge extends StatelessWidget {
  const _GroupPinBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.84),
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(Icons.push_pin, size: 19, color: scheme.primary),
        ),
      ),
    );
  }
}

class _SongCollectionPage extends StatelessWidget {
  const _SongCollectionPage({
    required this.title,
    required this.songs,
    required this.pinScope,
  });
  final String title;
  final List<Song> songs;
  final String pinScope;

  @override
  Widget build(BuildContext context) {
    context.select<PlaylistContentNotifier, int>(
      (notifier) => notifier.libraryRevision,
    );
    final backgroundSong = context.select<PlaylistContentNotifier, Song?>(
      (notifier) => notifier.currentSong,
    );
    final notifier = context.read<PlaylistContentNotifier>();
    final statistics = context.watch<StatisticsManager>();
    final playCounts = SongGroupPresentation.normalizedPlayCounts(
      statistics.statisticsData.songStats,
    );
    final sortedSongs = notifier.pinnedFirst(
      pinScope,
      SongGroupPresentation.sortByPlayCount(songs, playCounts),
    );
    final settings = context.watch<SettingsProvider>();
    final customBackgroundEnabled =
        settings.homeThemeImageEnabled &&
        settings.homeThemeImagePath != null &&
        settings.homeThemeImagePath!.isNotEmpty;
    final backgroundAlbumArt = backgroundSong == null
        ? null
        : notifier.displayCoverForSong(backgroundSong);
    final albumArtBackgroundEnabled =
        settings.followAlbumArtOnHome && backgroundAlbumArt != null;
    final useBackground = customBackgroundEnabled || albumArtBackgroundEnabled;

    final scaffold = Scaffold(
      backgroundColor: useBackground ? Colors.transparent : null,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: useBackground ? Colors.transparent : null,
        scrolledUnderElevation: useBackground ? 0 : null,
        actions: [
          IconButton(
            tooltip: '在$title中搜索',
            icon: const Icon(Icons.search),
            onPressed: () => showSearch<void>(
              context: context,
              delegate: _SongSearchDelegate(
                initialQuery: '',
                scope: _SongSearchScope.collection,
                sourceSongs: sortedSongs,
                onChanged: (_) {},
                onPlay: (results, index) =>
                    notifier.playFromDynamicList(results, index),
              ),
            ),
          ),
        ],
      ),
      body: _SongList(
        songs: sortedSongs,
        pinScope: pinScope,
        onPlay: (index) => notifier.playFromDynamicList(sortedSongs, index),
      ),
    );

    return CustomThemeBackground(
      path: settings.homeThemeImagePath,
      enabled: customBackgroundEnabled,
      dim: settings.homeThemeImageDim,
      blurSigma: settings.homeThemeImageBlur,
      coverBytes: backgroundAlbumArt,
      coverEnabled: albumArtBackgroundEnabled,
      coverDim: settings.homeAlbumArtBackgroundDim,
      coverBlurSigma: settings.homeAlbumArtBackgroundBlur,
      child: scaffold,
    );
  }
}

class _SongList extends StatelessWidget {
  const _SongList({
    required this.songs,
    required this.onPlay,
    this.showRemove = false,
    this.entranceAnimation,
    this.selectionMode = false,
    this.selectedPaths = const {},
    this.onToggleSelection,
    this.pinScope,
    this.groupByInitial = false,
  });
  final List<Song> songs;
  final Future<void> Function(int index) onPlay;
  final bool showRemove;
  final Animation<double>? entranceAnimation;
  final bool selectionMode;
  final Set<String> selectedPaths;
  final ValueChanged<Song>? onToggleSelection;
  final String? pinScope;
  final bool groupByInitial;

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) return const Center(child: Text('没有歌曲'));
    context.select<PlaylistContentNotifier, (int, int)>(
      (notifier) => (notifier.libraryRevision, notifier.playlistRevision),
    );
    final notifier = context.read<PlaylistContentNotifier>();
    final isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;

    Widget withPrefetch(Widget child, {required double itemExtent}) =>
        _ArtworkPrefetchViewport(
          songs: songs,
          itemExtent: itemExtent,
          child: child,
        );

    Widget buildSongTile(int index, {required bool grid}) {
      final song = songs[index];
      final isPinned =
          pinScope != null && notifier.isPinned(pinScope!, song.normalizedPath);
      final selected = selectedPaths.contains(
        song.normalizedPath.toLowerCase(),
      );
      final tile = AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        margin: grid ? const EdgeInsets.all(5) : EdgeInsets.zero,
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.secondaryContainer
              : grid
              ? Theme.of(context).colorScheme.surfaceContainerLow
              : Colors.transparent,
          borderRadius: grid ? BorderRadius.circular(20) : null,
        ),
        clipBehavior: grid ? Clip.antiAlias : Clip.none,
        child: Material(
          color: Colors.transparent,
          child: ListTile(
            contentPadding: EdgeInsets.symmetric(
              horizontal: grid ? 12 : 16,
              vertical: 3,
            ),
            horizontalTitleGap: grid ? 10 : 16,
            leading: _Cover(song: song),
            title: Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: grid ? Theme.of(context).textTheme.titleMedium : null,
            ),
            subtitle: Text(
              '${song.artist} · ${song.album}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: grid ? Theme.of(context).textTheme.bodySmall : null,
            ),
            trailing: selectionMode
                ? Checkbox(
                    value: selected,
                    onChanged: (_) => onToggleSelection?.call(song),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isPinned)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 36,
                          ),
                          icon: const Icon(Icons.push_pin, size: 18),
                          tooltip: '取消置顶',
                          onPressed: () => notifier.togglePinned(
                            pinScope!,
                            song.normalizedPath,
                          ),
                        ),
                      IconButton(
                        visualDensity: grid ? VisualDensity.compact : null,
                        constraints: grid
                            ? const BoxConstraints(minWidth: 36, minHeight: 36)
                            : null,
                        icon: const Icon(Icons.more_vert),
                        tooltip: '更多',
                        onPressed: () => _songActions(context, song, index),
                      ),
                    ],
                  ),
            onLongPress: () => selectionMode
                ? onToggleSelection?.call(song)
                : _songActions(context, song, index),
            onTap: () =>
                selectionMode ? onToggleSelection?.call(song) : onPlay(index),
          ),
        ),
      );
      final keyedTile = KeyedSubtree(
        key: ValueKey(song.normalizedPath),
        child: tile,
      );
      final animation = entranceAnimation;
      if (animation == null) return keyedTile;
      final group = index.clamp(0, 4);
      final start = group * 0.08;
      final end = (start + 0.55).clamp(0.0, 1.0);
      final distance = switch (group) {
        0 => 100.0,
        1 => 75.0,
        2 => 50.0,
        3 => 25.0,
        _ => 25.0,
      };
      return AnimatedBuilder(
        animation: animation,
        child: keyedTile,
        builder: (context, child) {
          final progress = Curves.easeOutCubic.transform(
            Interval(start, end).transform(animation.value),
          );
          return Opacity(
            opacity: progress,
            child: Transform.translate(
              offset: Offset(0, distance * (1 - progress)),
              child: child,
            ),
          );
        },
      );
    }

    final allIndices = List<int>.generate(songs.length, (index) => index);
    final songPartition = !selectionMode && pinScope != null
        ? SongGroupPresentation.separatePinned(
            allIndices,
            (index) =>
                notifier.isPinned(pinScope!, songs[index].normalizedPath),
          )
        : (pinned: <int>[], regular: allIndices);
    final pinnedIndices = songPartition.pinned;
    final regularIndices = songPartition.regular;

    Widget buildPinnedSongsView({
      required bool grid,
      SliverGridDelegate? gridDelegate,
    }) {
      Widget buildItems(List<int> indices) {
        if (grid) {
          return SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid(
              gridDelegate: gridDelegate!,
              delegate: SliverChildBuilderDelegate(
                (context, index) => buildSongTile(indices[index], grid: true),
                childCount: indices.length,
              ),
            ),
          );
        }
        return SliverList.builder(
          itemCount: indices.length,
          itemBuilder: (context, index) =>
              buildSongTile(indices[index], grid: false),
        );
      }

      return CustomScrollView(
        slivers: [
          // Pinned songs already occupy their own leading section and expose
          // their state through the row action. Start the content immediately
          // so a redundant marker does not leave a large empty header above it.
          buildItems(pinnedIndices),
          if (regularIndices.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 8),
                child: Divider(height: 1),
              ),
            ),
            buildItems(regularIndices),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 18)),
        ],
      );
    }

    Widget buildIndexedSongsView() {
      final sections = SongGroupPresentation.groupByInitial(
        regularIndices,
        (index) => songs[index].title,
      );

      Widget buildCompactSongCard(int songIndex) {
        final song = songs[songIndex];
        final selected = selectedPaths.contains(
          song.normalizedPath.toLowerCase(),
        );
        final isPinned =
            pinScope != null &&
            notifier.isPinned(pinScope!, song.normalizedPath);
        final scheme = Theme.of(context).colorScheme;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: selected
                ? scheme.secondaryContainer
                : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => selectionMode
                  ? onToggleSelection?.call(song)
                  : onPlay(songIndex),
              onLongPress: () => selectionMode
                  ? onToggleSelection?.call(song)
                  : _songActions(context, song, songIndex),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) => Stack(
                        fit: StackFit.expand,
                        children: [
                          _Cover(
                            song: song,
                            size: constraints.biggest.shortestSide,
                          ),
                          if (isPinned)
                            const Positioned(
                              top: 5,
                              right: 5,
                              child: _GroupPinBadge(),
                            ),
                          if (selectionMode)
                            Positioned(
                              top: 2,
                              right: 2,
                              child: Checkbox(
                                value: selected,
                                onChanged: (_) => onToggleSelection?.call(song),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 5, 6, 6),
                    child: Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      Widget buildItems(List<int> indices) => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 88,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: .76,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => buildCompactSongCard(indices[index]),
            childCount: indices.length,
          ),
        ),
      );

      return CustomScrollView(
        key: const ValueKey('library-indexed-song-list'),
        slivers: [
          if (pinnedIndices.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            buildItems(pinnedIndices),
          ],
          for (final section in sections.entries) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 5),
                child: Text(
                  section.key,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            buildItems(section.value),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 18)),
        ],
      );
    }

    if (groupByInitial) {
      return LayoutBuilder(
        builder: (context, constraints) {
          const horizontalPadding = 20.0;
          const spacing = 8.0;
          const maxTileExtent = 88.0;
          final availableWidth = math.max(
            maxTileExtent,
            constraints.maxWidth - horizontalPadding,
          );
          final columnCount = math.max(
            1,
            ((availableWidth + spacing) / (maxTileExtent + spacing)).ceil(),
          );
          final tileWidth =
              (availableWidth - spacing * (columnCount - 1)) / columnCount;
          final rowExtent = tileWidth / .76 + spacing;
          return withPrefetch(
            buildIndexedSongsView(),
            itemExtent: rowExtent / columnCount,
          );
        },
      );
    }

    if (isTablet) {
      return LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 500) {
            return withPrefetch(
              pinnedIndices.isNotEmpty
                  ? buildPinnedSongsView(grid: false)
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      itemCount: songs.length,
                      itemBuilder: (context, index) =>
                          buildSongTile(index, grid: false),
                    ),
              itemExtent: 72,
            );
          }
          final columns = (constraints.maxWidth / 360).ceil().clamp(2, 4);
          const gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 420,
            mainAxisExtent: 92,
          );
          return withPrefetch(
            pinnedIndices.isNotEmpty
                ? buildPinnedSongsView(grid: true, gridDelegate: gridDelegate)
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
                    gridDelegate: gridDelegate,
                    itemCount: songs.length,
                    itemBuilder: (context, index) =>
                        buildSongTile(index, grid: true),
                  ),
            itemExtent: 92 / columns,
          );
        },
      );
    }

    return withPrefetch(
      pinnedIndices.isNotEmpty
          ? buildPinnedSongsView(grid: false)
          : ListView.builder(
              itemCount: songs.length,
              itemBuilder: (context, index) =>
                  buildSongTile(index, grid: false),
            ),
      itemExtent: 72,
    );
  }

  void _songActions(
    BuildContext context,
    Song song,
    int index,
  ) => showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.play_arrow),
            title: const Text('立即播放'),
            onTap: () {
              Navigator.pop(sheetContext);
              onPlay(index);
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add),
            title: const Text('下一首播放'),
            onTap: () {
              context.read<PlaylistContentNotifier>().addToPlayingQueueNext(
                song,
              );
              Navigator.pop(sheetContext);
            },
          ),
          ListTile(
            leading: const Icon(Icons.queue),
            title: const Text('添加到播放队列'),
            onTap: () {
              context.read<PlaylistContentNotifier>().addToPlayingQueue(song);
              Navigator.pop(sheetContext);
            },
          ),
          if (onToggleSelection != null)
            ListTile(
              leading: const Icon(Icons.checklist),
              title: const Text('多选'),
              onTap: () {
                Navigator.pop(sheetContext);
                onToggleSelection!(song);
              },
            ),
          if (pinScope != null)
            ListTile(
              leading: Icon(
                context.read<PlaylistContentNotifier>().isPinned(
                      pinScope!,
                      song.normalizedPath,
                    )
                    ? Icons.push_pin_outlined
                    : Icons.push_pin,
              ),
              title: Text(
                context.read<PlaylistContentNotifier>().isPinned(
                      pinScope!,
                      song.normalizedPath,
                    )
                    ? '取消置顶'
                    : '置顶',
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                await context.read<PlaylistContentNotifier>().togglePinned(
                  pinScope!,
                  song.normalizedPath,
                );
              },
            ),
          if (showRemove)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('从当前歌单移除'),
              onTap: () {
                final notifier = context.read<PlaylistContentNotifier>();
                final actualIndex = notifier.currentPlaylistSongs.indexWhere(
                  (item) =>
                      item.normalizedPath.toLowerCase() ==
                      song.normalizedPath.toLowerCase(),
                );
                if (actualIndex >= 0) {
                  notifier.removeSongFromCurrentPlaylist(actualIndex);
                }
                Navigator.pop(sheetContext);
              },
            ),
        ],
      ),
    ),
  );
}

class _ArtworkPrefetchViewport extends StatefulWidget {
  const _ArtworkPrefetchViewport({
    required this.songs,
    required this.itemExtent,
    required this.child,
  });

  final List<Song> songs;
  final double itemExtent;
  final Widget child;

  @override
  State<_ArtworkPrefetchViewport> createState() =>
      _ArtworkPrefetchViewportState();
}

class _ArtworkPrefetchViewportState extends State<_ArtworkPrefetchViewport> {
  Timer? _throttle;
  final Stopwatch _scrollClock = Stopwatch()..start();
  double _lastPixels = 0;
  int _lastMicros = 0;
  double _velocity = 0;
  double _pendingPixels = 0;
  double _pendingViewport = 0;
  int _generation = 0;
  bool _initialScheduled = false;
  int? _lastPrefetchSignature;

  bool _onScroll(ScrollNotification notification) {
    final now = _scrollClock.elapsedMicroseconds;
    final elapsed = now - _lastMicros;
    if (elapsed > 0 && _lastMicros != 0) {
      _velocity =
          (notification.metrics.pixels - _lastPixels) /
          (elapsed / Duration.microsecondsPerSecond);
    }
    _lastMicros = now;
    _lastPixels = notification.metrics.pixels;
    _pendingPixels = notification.metrics.pixels;
    _pendingViewport = notification.metrics.viewportDimension;
    InteractionPerformanceController.instance.pulse(
      _velocity.abs() >= 1200
          ? InteractionPhase.fling
          : InteractionPhase.interacting,
      settleAfter: notification is ScrollEndNotification
          ? const Duration(milliseconds: 90)
          : const Duration(milliseconds: 180),
    );
    _throttle ??= Timer(const Duration(milliseconds: 32), () {
      _throttle = null;
      _prefetch(
        pixels: _pendingPixels,
        viewport: _pendingViewport,
        velocity: _velocity,
      );
    });
    return false;
  }

  void _prefetch({
    required double pixels,
    required double viewport,
    required double velocity,
  }) {
    if (!mounted || widget.songs.isEmpty) return;
    final plan = planArtworkPrefetch(
      itemCount: widget.songs.length,
      pixels: pixels,
      viewportPixels: viewport,
      itemExtent: widget.itemExtent,
      velocityPixelsPerSecond: velocity,
    );
    final end = (plan.end - plan.start > 96) ? plan.start + 96 : plan.end;
    final firstVisible = (pixels / widget.itemExtent).floor().clamp(
      0,
      widget.songs.length - 1,
    );
    final visibleCount = math.max(1, (viewport / widget.itemExtent).ceil());
    final lastVisible = math.min(
      widget.songs.length,
      firstVisible + visibleCount,
    );
    final direction = velocity == 0 ? 0 : velocity.sign.toInt();
    final signature = Object.hash(
      plan.start,
      end,
      firstVisible,
      lastVisible,
      direction,
      widget.songs[plan.start].normalizedPath,
      widget.songs[end - 1].normalizedPath,
      widget.songs[firstVisible].normalizedPath,
    );
    if (_lastPrefetchSignature == signature) return;
    _lastPrefetchSignature = signature;
    final generation = ++_generation;

    final notifier = context.read<PlaylistContentNotifier>();
    notifier.beginArtworkPrefetchWindow();

    // Only visible rows need completion futures and Flutter image precaching.
    // Near/far rows are queued in batches below, avoiding dozens of short-lived
    // completers every time a fast fling advances the viewport.
    for (var index = firstVisible; index < lastVisible; index++) {
      final song = widget.songs[index];
      notifier
          .ensureSongThumbnail(
            song.filePath,
            priority: ArtworkRequestPriority.visible,
          )
          .then((bytes) {
            if (!mounted || generation != _generation || bytes == null) return;
            precacheImage(CoverMemoryImage(bytes, targetPixels: 192), context);
          });
    }

    final near = <Song>[];
    final far = <Song>[];
    for (var actualIndex = plan.start; actualIndex < end; actualIndex++) {
      if (actualIndex >= firstVisible && actualIndex < lastVisible) continue;
      final distance = (actualIndex - plan.predictedIndex).abs();
      final target = distance <= visibleCount * 2 ? near : far;
      target.add(widget.songs[actualIndex]);
    }
    notifier.prefetchSongCovers(near, priority: ArtworkRequestPriority.near);
    notifier.prefetchSongCovers(far, priority: ArtworkRequestPriority.far);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (!_initialScheduled && constraints.maxHeight.isFinite) {
        _initialScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _prefetch(pixels: 0, viewport: constraints.maxHeight, velocity: 0);
        });
      }
      return NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: widget.child,
      );
    },
  );

  @override
  void dispose() {
    _generation++;
    _lastPrefetchSignature = null;
    _throttle?.cancel();
    super.dispose();
  }
}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({this.translucent = false});
  final bool translucent;
  @override
  Widget build(BuildContext context) {
    final playback = context
        .select<
          PlaylistContentNotifier,
          ({Song? song, bool isPlaying, Duration totalDuration})
        >(
          (notifier) => (
            song: notifier.currentSong,
            isPlaying: notifier.isPlaying,
            totalDuration: notifier.totalDuration,
          ),
        );
    final notifier = context.read<PlaylistContentNotifier>();
    final song = playback.song;
    if (song == null) return const SizedBox.shrink();
    final isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;
    if (isTablet) {
      final totalMs = playback.totalDuration.inMilliseconds;
      return _NowPlayingArtworkWarmup(
        song: song,
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerHigh.withValues(
            alpha: translucent ? 0.82 : 1,
          ),
          child: InkWell(
            onTap: () => _openNowPlaying(context),
            child: SizedBox(
              height: 88,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    NowPlayingCoverHero(
                      normalizedSongPath: song.normalizedPath,
                      child: _Cover(song: song, size: 58),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 5),
                          ValueListenableBuilder<Duration>(
                            valueListenable: notifier.positionListenable,
                            builder: (context, position, _) {
                              final positionMs = position.inMilliseconds.clamp(
                                0,
                                totalMs > 0 ? totalMs : 1,
                              );
                              return LinearProgressIndicator(
                                value: totalMs > 0 ? positionMs / totalMs : 0,
                                minHeight: 3,
                                borderRadius: BorderRadius.circular(3),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 22),
                    IconButton(
                      tooltip: '上一首',
                      icon: const Icon(Icons.skip_previous),
                      onPressed: () => notifier.playPrevious(),
                    ),
                    PlayPauseButton(
                      isPlaying: playback.isPlaying,
                      tooltip: playback.isPlaying ? '暂停' : '播放',
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.secondaryContainer,
                      onPressed: playback.isPlaying
                          ? notifier.pause
                          : notifier.play,
                    ),
                    IconButton(
                      tooltip: '下一首',
                      icon: const Icon(Icons.skip_next),
                      onPressed: () => notifier.playNext(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return _NowPlayingArtworkWarmup(
      song: song,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh.withValues(
          alpha: translucent ? 0.82 : 1,
        ),
        child: ListTile(
          leading: NowPlayingCoverHero(
            normalizedSongPath: song.normalizedPath,
            child: _Cover(song: song),
          ),
          title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _openNowPlaying(context),
          trailing: PlayPauseButton(
            isPlaying: playback.isPlaying,
            size: 34,
            padding: const EdgeInsets.all(5),
            tooltip: playback.isPlaying ? '暂停' : '播放',
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            onPressed: playback.isPlaying ? notifier.pause : notifier.play,
          ),
        ),
      ),
    );
  }
}

void _openNowPlaying(BuildContext context) {
  final notifier = context.read<PlaylistContentNotifier>();
  final settings = context.read<SettingsProvider>();
  final song = notifier.currentSong;
  final startsOnCover =
      settings.playbackInitialView == PlaybackInitialView.cover;
  final initialCoverHeroReady =
      startsOnCover &&
      song != null &&
      _isNowPlayingArtworkPrepared(notifier, song);
  notifier.postponeForegroundArtworkRecovery();
  InteractionPerformanceController.instance.pulse(
    InteractionPhase.transition,
    settleAfter: const Duration(milliseconds: 460),
  );
  unawaited(
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        // A route snapshot can preserve placeholder list thumbnails captured
        // during the push and briefly replay them on pop. The home subtree is a
        // repaint boundary, so rendering it live keeps the transition accurate
        // without causing the song list to repaint every frame.
        allowSnapshotting: false,
        builder: (_) =>
            _NowPlayingPage(initialCoverHeroReady: initialCoverHeroReady),
      ),
    ),
  );
}

class _NowPlayingArtworkWarmup extends StatelessWidget {
  const _NowPlayingArtworkWarmup({required this.song, required this.child});

  final Song song;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class _PreparedPlaybackArtwork {
  const _PreparedPlaybackArtwork({
    required this.path,
    required this.bytes,
    required this.targetPixels,
    required this.cacheGeneration,
  });

  final String path;
  final Uint8List bytes;
  final int targetPixels;
  final int cacheGeneration;
}

/// Immutable background input used while the playback route is moving.
///
/// The foreground cover is deliberately not frozen: its decode can complete
/// at full speed while this lightweight, blurred backdrop remains stable.
class _PlaybackBackgroundFrame {
  const _PlaybackBackgroundFrame({
    required this.path,
    required this.customImageEnabled,
    required this.customImageDim,
    required this.customImageBlur,
    required this.coverBytes,
    required this.coverEnabled,
    required this.coverDim,
    required this.coverBlur,
    required this.usePlaybackTheme,
  });

  final String? path;
  final bool customImageEnabled;
  final double customImageDim;
  final double customImageBlur;
  final Uint8List? coverBytes;
  final bool coverEnabled;
  final double coverDim;
  final double coverBlur;
  final bool usePlaybackTheme;
}

_PreparedPlaybackArtwork? _preparedPlaybackArtwork;
_PreparedPlaybackArtwork? _previousPreparedPlaybackArtwork;
String? _playbackArtworkHandoffTargetPath;
final ValueNotifier<int> _preparedPlaybackArtworkSignal = ValueNotifier(0);

class _PlaybackArtworkPreparationCoordinator extends StatefulWidget {
  const _PlaybackArtworkPreparationCoordinator({required this.child});

  final Widget child;

  @override
  State<_PlaybackArtworkPreparationCoordinator> createState() =>
      _PlaybackArtworkPreparationCoordinatorState();
}

class _PlaybackArtworkPreparationCoordinatorState
    extends State<_PlaybackArtworkPreparationCoordinator> {
  PlaylistContentNotifier? _notifier;
  ValueListenable<String?>? _targetListenable;
  ValueListenable<int>? _artworkRecoveryListenable;
  ValueListenable<int>? _prewarmTargetListenable;
  Listenable? _coverListenable;
  final Map<String, ({Listenable listenable, VoidCallback callback})>
  _prewarmCoverListeners = {};
  final Map<String, int> _prewarmedArtworkKeys = {};
  int _generation = 0;
  int _prewarmGeneration = 0;
  String? _observedPath;
  bool _decodeInFlight = false;
  bool _retryAfterDecode = false;
  bool _prewarmDecodeInFlight = false;
  bool _retryPrewarmDecode = false;
  Timer? _handoffExpiryTimer;
  static const _maximumPreviousCoverHandoff = Duration(milliseconds: 220);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notifier = context.read<PlaylistContentNotifier>();
    if (!identical(_notifier, notifier)) {
      _targetListenable?.removeListener(_handleTargetChanged);
      _artworkRecoveryListenable?.removeListener(_handleArtworkRecovery);
      _prewarmTargetListenable?.removeListener(_handlePrewarmTargetsChanged);
      _detachPrewarmCoverListeners();
      _notifier = notifier;
      _targetListenable = notifier.playbackArtworkTargetListenable
        ..addListener(_handleTargetChanged);
      _artworkRecoveryListenable = notifier.artworkRecoveryListenable
        ..addListener(_handleArtworkRecovery);
      _prewarmTargetListenable = notifier.playbackArtworkPrewarmListenable
        ..addListener(_handlePrewarmTargetsChanged);
    }
    _syncTarget();
    _syncPrewarmCoverListeners();
  }

  void _handleTargetChanged() {
    _generation++;
    _syncTarget();
  }

  void _syncTarget() {
    final path = _targetListenable?.value;
    if (_observedPath == path) {
      _schedulePreparation();
      return;
    }
    _coverListenable?.removeListener(_handleCoverChanged);
    _coverListenable = null;
    _observedPath = path;
    _beginArtworkHandoff(path);
    if (path == null) {
      if (_preparedPlaybackArtwork != null) {
        _preparedPlaybackArtwork = null;
        _previousPreparedPlaybackArtwork = null;
        _preparedPlaybackArtworkSignal.value++;
      }
      return;
    }
    final notifier = _notifier;
    if (notifier == null) return;
    _coverListenable = notifier.coverListenableForSongPath(path)
      ..addListener(_handleCoverChanged);
    _handleCoverChanged();
  }

  void _beginArtworkHandoff(String? targetPath) {
    _handoffExpiryTimer?.cancel();
    _handoffExpiryTimer = null;
    _playbackArtworkHandoffTargetPath = null;
    if (targetPath == null || _preparedPlaybackArtwork?.path == targetPath) {
      return;
    }
    final retained =
        _preparedPlaybackArtwork ?? _previousPreparedPlaybackArtwork;
    if (retained == null) return;
    _playbackArtworkHandoffTargetPath = targetPath;
    _handoffExpiryTimer = Timer(_maximumPreviousCoverHandoff, () {
      _handoffExpiryTimer = null;
      if (!mounted ||
          _observedPath != targetPath ||
          _playbackArtworkHandoffTargetPath != targetPath) {
        return;
      }
      _playbackArtworkHandoffTargetPath = null;
      _preparedPlaybackArtworkSignal.value++;
    });
  }

  void _finishArtworkHandoff(String path) {
    if (_playbackArtworkHandoffTargetPath != path) return;
    _handoffExpiryTimer?.cancel();
    _handoffExpiryTimer = null;
    _playbackArtworkHandoffTargetPath = null;
  }

  void _clearPreparedArtwork() {
    if (_preparedPlaybackArtwork == null &&
        _previousPreparedPlaybackArtwork == null) {
      return;
    }
    _preparedPlaybackArtwork = null;
    _previousPreparedPlaybackArtwork = null;
    _finishArtworkHandoff(_observedPath ?? '');
    _preparedPlaybackArtworkSignal.value++;
  }

  void _handleCoverChanged() {
    final notifier = _notifier;
    final path = _observedPath;
    if (notifier == null || path == null) return;
    final artwork = notifier.displayPlaybackCoverForPath(path);
    if (artwork == null || artwork.isEmpty) {
      if (notifier.artworkResolutionStateForPath(path) ==
          ArtworkResolutionState.unavailable) {
        _clearPreparedArtwork();
      }
      return;
    }
    _schedulePreparation();
  }

  void _handleArtworkRecovery() {
    final notifier = _notifier;
    if (notifier == null) return;
    _generation++;
    _prewarmGeneration++;
    _prewarmedArtworkKeys.clear();
    if (notifier.isAppForeground) {
      _schedulePreparation();
      _schedulePrewarmPreparation();
    }
  }

  void _handlePrewarmTargetsChanged() {
    _prewarmGeneration++;
    _syncPrewarmCoverListeners();
  }

  void _detachPrewarmCoverListeners() {
    for (final entry in _prewarmCoverListeners.values) {
      entry.listenable.removeListener(entry.callback);
    }
    _prewarmCoverListeners.clear();
    _prewarmedArtworkKeys.clear();
  }

  void _syncPrewarmCoverListeners() {
    final notifier = _notifier;
    if (notifier == null) return;
    final desired = notifier.playbackArtworkPrewarmPaths.toSet();
    for (final path in _prewarmCoverListeners.keys.toSet().difference(
      desired,
    )) {
      final entry = _prewarmCoverListeners.remove(path);
      if (entry != null) entry.listenable.removeListener(entry.callback);
      _prewarmedArtworkKeys.remove(path);
    }
    for (final path in desired.difference(
      _prewarmCoverListeners.keys.toSet(),
    )) {
      void callback() => _schedulePrewarmPreparation();
      final listenable = notifier.coverListenableForSongPath(path)
        ..addListener(callback);
      _prewarmCoverListeners[path] = (
        listenable: listenable,
        callback: callback,
      );
    }
    _schedulePrewarmPreparation();
  }

  int _targetPixelsForPlaybackArtwork() {
    final logicalSize = MediaQuery.sizeOf(context).shortestSide >= 600
        ? 520.0
        : 360.0;
    return playbackArtworkTargetPixels(
      logicalSize: logicalSize,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
  }

  void _schedulePreparation() {
    final notifier = _notifier;
    final path = _observedPath;
    if (notifier == null || path == null || !notifier.isAppForeground) return;
    final artwork = notifier.displayPlaybackCoverForPath(path);
    if (artwork == null || artwork.isEmpty) return;
    final targetPixels = _targetPixelsForPlaybackArtwork();
    final cacheGeneration = notifier.artworkImageCacheGeneration;
    final prepared = _preparedPlaybackArtwork;
    if (prepared != null &&
        prepared.path == path &&
        identical(prepared.bytes, artwork) &&
        prepared.targetPixels == targetPixels &&
        prepared.cacheGeneration == cacheGeneration) {
      return;
    }
    if (_decodeInFlight) {
      _retryAfterDecode = true;
      return;
    }
    _decodeInFlight = true;
    final generation = _generation;
    unawaited(
      _prepareArtwork(
        notifier: notifier,
        path: path,
        artwork: artwork,
        targetPixels: targetPixels,
        cacheGeneration: cacheGeneration,
        generation: generation,
      ),
    );
  }

  Future<void> _prepareArtwork({
    required PlaylistContentNotifier notifier,
    required String path,
    required Uint8List artwork,
    required int targetPixels,
    required int cacheGeneration,
    required int generation,
  }) async {
    try {
      // Start on the next frame instead of waiting behind the 280 ms transport
      // protection window. Flutter performs the codec work asynchronously and
      // this coordinator still serializes exact decodes, keeping frame cost
      // bounded while removing the visible old-cover delay.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted ||
          generation != _generation ||
          path != _observedPath ||
          !notifier.isAppForeground ||
          cacheGeneration != notifier.artworkImageCacheGeneration) {
        return;
      }
      Object? decodeError;
      StackTrace? decodeStackTrace;
      await precacheImage(
        CoverMemoryImage(artwork, targetPixels: targetPixels),
        context,
        onError: (error, stackTrace) {
          decodeError = error;
          decodeStackTrace = stackTrace;
        },
      );
      if (decodeError != null) {
        Error.throwWithStackTrace(
          decodeError!,
          decodeStackTrace ?? StackTrace.current,
        );
      }
      if (!mounted ||
          generation != _generation ||
          path != _observedPath ||
          cacheGeneration != notifier.artworkImageCacheGeneration) {
        return;
      }
      final previousPrepared = _preparedPlaybackArtwork;
      if (previousPrepared != null && previousPrepared.path != path) {
        _previousPreparedPlaybackArtwork = previousPrepared;
      }
      _preparedPlaybackArtwork = _PreparedPlaybackArtwork(
        path: path,
        bytes: artwork,
        targetPixels: targetPixels,
        cacheGeneration: cacheGeneration,
      );
      _finishArtworkHandoff(path);
      _preparedPlaybackArtworkSignal.value++;
    } catch (_) {
      if (mounted && generation == _generation && path == _observedPath) {
        notifier.reportUndecodableCover(path, artwork);
        if (notifier.artworkResolutionStateForPath(path) ==
            ArtworkResolutionState.unavailable) {
          _clearPreparedArtwork();
        }
      }
    } finally {
      _decodeInFlight = false;
      final retry = _retryAfterDecode;
      _retryAfterDecode = false;
      if (mounted && (retry || generation != _generation)) {
        _schedulePreparation();
      }
      if (mounted) _schedulePrewarmPreparation();
    }
  }

  void _schedulePrewarmPreparation() {
    final notifier = _notifier;
    if (notifier == null || !notifier.isAppForeground) return;
    if (_decodeInFlight || _prewarmDecodeInFlight) {
      _retryPrewarmDecode = true;
      return;
    }
    _prewarmDecodeInFlight = true;
    final generation = _prewarmGeneration;
    unawaited(
      _preparePrewarmedArtwork(notifier: notifier, generation: generation),
    );
  }

  Future<void> _preparePrewarmedArtwork({
    required PlaylistContentNotifier notifier,
    required int generation,
  }) async {
    try {
      final targetPixels = _targetPixelsForPlaybackArtwork();
      final cacheGeneration = notifier.artworkImageCacheGeneration;
      final paths = notifier.playbackArtworkPrewarmPaths;
      for (final path in paths) {
        if (!mounted ||
            generation != _prewarmGeneration ||
            !notifier.isAppForeground ||
            !notifier.playbackArtworkPrewarmPaths.contains(path)) {
          return;
        }
        final artwork = notifier.displayPlaybackCoverForPath(path);
        if (artwork == null || artwork.isEmpty) continue;
        final preparationKey = Object.hash(
          identityHashCode(artwork),
          targetPixels,
          cacheGeneration,
        );
        final imageProvider = CoverMemoryImage(
          artwork,
          targetPixels: targetPixels,
        );
        final imageCacheStatus = PaintingBinding.instance.imageCache
            .statusForKey(imageProvider);
        if (_prewarmedArtworkKeys[path] == preparationKey &&
            imageCacheStatus.tracked) {
          continue;
        }

        final lease = await InteractionPerformanceController.instance
            .acquireIdleWork(
              priority: InteractionWorkPriority.background,
              isStillNeeded: () =>
                  mounted &&
                  generation == _prewarmGeneration &&
                  notifier.isAppForeground &&
                  notifier.playbackArtworkPrewarmPaths.contains(path),
            );
        try {
          if (!lease.isGranted ||
              !mounted ||
              generation != _prewarmGeneration ||
              cacheGeneration != notifier.artworkImageCacheGeneration ||
              !notifier.playbackArtworkPrewarmPaths.contains(path)) {
            continue;
          }
          Object? decodeError;
          await precacheImage(
            imageProvider,
            context,
            onError: (error, _) => decodeError = error,
          );
          if (decodeError == null &&
              mounted &&
              generation == _prewarmGeneration &&
              cacheGeneration == notifier.artworkImageCacheGeneration) {
            _prewarmedArtworkKeys[path] = preparationKey;
          }
        } finally {
          lease.release();
        }
      }
    } finally {
      _prewarmDecodeInFlight = false;
      final retry = _retryPrewarmDecode;
      _retryPrewarmDecode = false;
      if (mounted && (retry || generation != _prewarmGeneration)) {
        _schedulePrewarmPreparation();
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _handoffExpiryTimer?.cancel();
    if (_playbackArtworkHandoffTargetPath == _observedPath) {
      _playbackArtworkHandoffTargetPath = null;
    }
    _targetListenable?.removeListener(_handleTargetChanged);
    _artworkRecoveryListenable?.removeListener(_handleArtworkRecovery);
    _prewarmTargetListenable?.removeListener(_handlePrewarmTargetsChanged);
    _coverListenable?.removeListener(_handleCoverChanged);
    _detachPrewarmCoverListeners();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

bool _isNowPlayingArtworkPrepared(PlaylistContentNotifier notifier, Song song) {
  final prepared = _preparedPlaybackArtwork;
  return prepared != null &&
      prepared.path == song.normalizedPath &&
      prepared.cacheGeneration == notifier.artworkImageCacheGeneration;
}

class _NowPlayingPage extends StatefulWidget {
  const _NowPlayingPage({required this.initialCoverHeroReady});

  final bool initialCoverHeroReady;

  @override
  State<_NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<_NowPlayingPage>
    with TickerProviderStateMixin {
  static const _playbackGlassBlur = 7.0;
  static const _playbackGlassFillAlpha = .10;
  static const _playbackGlassBorderAlpha = .72;
  static const _coverExitDuration = Duration(milliseconds: 210);
  static const _coverEnterDuration = Duration(milliseconds: 155);
  static const _lyricsContentEnterDuration = Duration(milliseconds: 140);
  static const _lyricsContentExitDuration = Duration(milliseconds: 100);

  bool _showLyrics = false;
  bool _lyricBrowseTapHandled = false;
  bool _coverLayerBuilt = true;
  bool _lyricsLayerBuilt = false;
  bool _lyricsRealtimeVisualsEnabled = false;
  final ValueNotifier<int> _frozenLyricLineIndex = ValueNotifier(0);
  final MobileLyricsListController _lyricsListController =
      MobileLyricsListController();
  late final AnimationController _coverTransitionController;
  late final AnimationController _lyricsContentTransitionController;
  final List<Timer> _visualTransitionTimers = [];
  int _visualTransitionRevision = 0;
  int _lyricsEntryRevision = 0;
  final ValueNotifier<double?> _seekPosition = ValueNotifier(null);
  bool _isDraggingSeek = false;
  int _seekSessionId = 0;
  Timer? _seekSettleTimer;
  Timer? _edgeSeekTimer;
  Stopwatch? _edgeSeekStopwatch;
  double _edgeSeekOriginMs = 0;
  double _edgeSeekTargetMs = 0;
  int _edgeSeekDirection = 0;
  bool _edgeSeekWasPlaying = false;
  double _edgeSeekBaseRate = 1;
  double _edgeSeekEffectiveRate = 2;
  Future<void>? _edgePlaybackSetup;
  String? _lastSongPath;
  Uint8List? _stablePlaybackCover;
  String? _stablePlaybackCoverPath;
  PlaylistContentNotifier? _playbackCoverNotifier;
  Listenable? _playbackCoverListenable;
  String? _playbackCoverListenablePath;
  final Map<int, Offset> _lyricPointers = {};
  final Map<int, Offset> _lyricPointerOrigins = {};
  double? _lyricPinchStartDistance;
  double? _lyricPinchStartFontSize;
  Timer? _lyricCopyHoldTimer;
  bool _lyricCopyGestureTriggered = false;
  Animation<double>? _routeAnimation;
  bool _routeTransitionComplete = false;
  bool _routeTransitionActive = true;
  _PlaybackBackgroundFrame? _renderedPlaybackBackground;
  _PlaybackBackgroundFrame? _pendingPlaybackBackground;

  @override
  void initState() {
    super.initState();
    _preparedPlaybackArtworkSignal.addListener(
      _handlePreparedPlaybackArtworkChanged,
    );
    _coverTransitionController = AnimationController(
      vsync: this,
      duration: _coverExitDuration,
    );
    _lyricsContentTransitionController = AnimationController(
      vsync: this,
      duration: _lyricsContentEnterDuration,
    );
    _showLyrics =
        context.read<SettingsProvider>().playbackInitialView ==
        PlaybackInitialView.lyrics;
    _coverLayerBuilt = !_showLyrics;
    _lyricsLayerBuilt = _showLyrics;
    _lyricsRealtimeVisualsEnabled = false;
    final initialVisualValue = _showLyrics ? 1.0 : 0.0;
    _coverTransitionController.value = initialVisualValue;
    _lyricsContentTransitionController.value = initialVisualValue;
  }

  void _handlePreparedPlaybackArtworkChanged() {
    // Decoding continues globally during a pop, but there is no value in
    // invalidating the disappearing route for a frame the user cannot keep.
    if (mounted && _routeAnimation?.status != AnimationStatus.reverse) {
      setState(() {});
    }
  }

  void _handlePlaybackCoverChanged() {
    if (mounted && _routeAnimation?.status != AnimationStatus.reverse) {
      setState(() {});
    }
  }

  _PlaybackBackgroundFrame _resolvePlaybackBackground(
    _PlaybackBackgroundFrame candidate,
  ) {
    _pendingPlaybackBackground = candidate;
    if (_renderedPlaybackBackground == null || !_routeTransitionActive) {
      _renderedPlaybackBackground = candidate;
    }
    return _renderedPlaybackBackground!;
  }

  void _syncPlaybackCoverListenable(
    PlaylistContentNotifier notifier,
    String songPath,
  ) {
    if (identical(_playbackCoverNotifier, notifier) &&
        _playbackCoverListenablePath == songPath) {
      return;
    }
    _playbackCoverListenable?.removeListener(_handlePlaybackCoverChanged);
    _playbackCoverNotifier = notifier;
    _playbackCoverListenablePath = songPath;
    _playbackCoverListenable = notifier.coverListenableForSongPath(songPath)
      ..addListener(_handlePlaybackCoverChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final routeAnimation = ModalRoute.of(context)?.animation;
    if (identical(routeAnimation, _routeAnimation)) return;
    _routeAnimation?.removeStatusListener(_handleRouteAnimationStatus);
    _routeAnimation = routeAnimation;
    _routeTransitionComplete =
        routeAnimation == null ||
        routeAnimation.status == AnimationStatus.completed;
    _routeTransitionActive = !_routeTransitionComplete;
    _lyricsRealtimeVisualsEnabled = shouldRunNowPlayingLyricsRealtime(
      showLyrics: _showLyrics,
      routeTransitionActive: _routeTransitionActive,
    );
    routeAnimation?.addStatusListener(_handleRouteAnimationStatus);
  }

  void _handleRouteAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.forward ||
        status == AnimationStatus.reverse) {
      // Push and pop both render the home and playback routes. Protect the
      // complete bidirectional animation so queued artwork, palette, lyric and
      // persistence work cannot start during a reverse transition.
      InteractionPerformanceController.instance.pulse(
        InteractionPhase.transition,
        settleAfter: const Duration(milliseconds: 520),
      );
      _routeTransitionActive = true;
      if (_lyricsRealtimeVisualsEnabled && mounted) {
        setState(() => _lyricsRealtimeVisualsEnabled = false);
      }
      return;
    }
    if (status != AnimationStatus.completed) return;
    if (!mounted) return;
    final pendingBackground = _pendingPlaybackBackground;
    setState(() {
      _routeTransitionComplete = true;
      _routeTransitionActive = false;
      if (pendingBackground != null) {
        _renderedPlaybackBackground = pendingBackground;
      }
      _lyricsRealtimeVisualsEnabled = shouldRunNowPlayingLyricsRealtime(
        showLyrics: _showLyrics,
        routeTransitionActive: _routeTransitionActive,
      );
    });
  }

  void _runVisualTransition({required bool showLyrics}) {
    InteractionPerformanceController.instance.pulse(
      InteractionPhase.transition,
      // The longest visual branch is 240 ms (100 ms delay + 140 ms enter).
      // Release directly afterwards so exact artwork preparation does not wait
      // through an additional idle window when the user changes songs.
      settleAfter: const Duration(milliseconds: 250),
    );
    final revision = ++_visualTransitionRevision;
    _cancelVisualTransitionTimers();
    _coverTransitionController.stop(canceled: false);
    _lyricsContentTransitionController.stop(canceled: false);

    void schedule(Duration delay, VoidCallback action) {
      if (delay == Duration.zero) {
        action();
        return;
      }
      _visualTransitionTimers.add(
        Timer(delay, () {
          if (!mounted || revision != _visualTransitionRevision) return;
          action();
        }),
      );
    }

    if (showLyrics) {
      schedule(
        Duration.zero,
        () => _animateVisualLayer(
          _coverTransitionController,
          target: 1,
          fullDuration: _coverExitDuration,
          curve: Curves.easeOutCubic,
        ),
      );
      schedule(
        const Duration(milliseconds: 100),
        () => _animateVisualLayer(
          _lyricsContentTransitionController,
          target: 1,
          fullDuration: _lyricsContentEnterDuration,
          curve: Curves.easeOutCubic,
        ),
      );
      schedule(const Duration(milliseconds: 245), () {
        if (!_showLyrics || _lyricsRealtimeVisualsEnabled) return;
        setState(() => _lyricsRealtimeVisualsEnabled = true);
      });
    } else {
      schedule(
        Duration.zero,
        () => _animateVisualLayer(
          _lyricsContentTransitionController,
          target: 0,
          fullDuration: _lyricsContentExitDuration,
          curve: Curves.easeOutCubic,
        ),
      );
      schedule(
        const Duration(milliseconds: 65),
        () => _animateVisualLayer(
          _coverTransitionController,
          target: 0,
          fullDuration: _coverEnterDuration,
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  void _animateVisualLayer(
    AnimationController controller, {
    required double target,
    required Duration fullDuration,
    required Curve curve,
  }) {
    final remaining = (target - controller.value).abs();
    if (remaining <= 0.0001) {
      controller.value = target;
      return;
    }
    final duration = Duration(
      microseconds: (fullDuration.inMicroseconds * remaining).round().clamp(
        1,
        fullDuration.inMicroseconds,
      ),
    );
    controller.animateTo(target, duration: duration, curve: curve);
  }

  void _cancelVisualTransitionTimers() {
    for (final timer in _visualTransitionTimers) {
      timer.cancel();
    }
    _visualTransitionTimers.clear();
  }

  @override
  void dispose() {
    _preparedPlaybackArtworkSignal.removeListener(
      _handlePreparedPlaybackArtworkChanged,
    );
    _routeAnimation?.removeStatusListener(_handleRouteAnimationStatus);
    _seekSettleTimer?.cancel();
    _edgeSeekTimer?.cancel();
    _edgeSeekStopwatch?.stop();
    _lyricCopyHoldTimer?.cancel();
    _playbackCoverListenable?.removeListener(_handlePlaybackCoverChanged);
    _cancelVisualTransitionTimers();
    _coverTransitionController.dispose();
    _lyricsContentTransitionController.dispose();
    _frozenLyricLineIndex.dispose();
    _seekPosition.dispose();
    super.dispose();
  }

  Future<void> _seekToBrowsedLyric(
    Duration target,
    PlaylistContentNotifier notifier,
  ) async {
    final totalMs = notifier.totalDuration.inMilliseconds.toDouble();
    final targetMs = target.inMilliseconds
        .toDouble()
        .clamp(0, totalMs > 0 ? totalMs : target.inMilliseconds.toDouble())
        .toDouble();
    final sessionId = ++_seekSessionId;
    _seekSettleTimer?.cancel();
    _isDraggingSeek = false;
    _seekPosition.value = targetMs;
    _lyricsListController.settleOn(target);
    for (var attempt = 0; attempt < 2; attempt++) {
      await notifier.mediaPlayer.seek(Duration(milliseconds: targetMs.round()));
      if (!mounted || sessionId != _seekSessionId) return;
      if (attempt == 0 && !notifier.isPlaying) {
        await notifier.play();
        if (!mounted || sessionId != _seekSessionId) return;
      }
      if (attempt > 0) break;
      await Future<void>.delayed(const Duration(milliseconds: 160));
      if (!mounted || sessionId != _seekSessionId) return;
      final actualMs = notifier.currentPosition.inMilliseconds.toDouble();
      if ((actualMs - targetMs).abs() <= 1000) break;
    }
    if (!notifier.isPlaying) await notifier.play();
    if (!mounted || sessionId != _seekSessionId) return;
    _waitForSeekPosition(notifier, sessionId, targetMs);
  }

  void _startEdgeSeek(int direction, PlaylistContentNotifier notifier) {
    final totalMs = notifier.totalDuration.inMilliseconds.toDouble();
    if (totalMs <= 0 || direction == 0) return;

    _edgeSeekTimer?.cancel();
    _edgeSeekStopwatch?.stop();
    _seekSettleTimer?.cancel();
    _seekSessionId++;
    _edgeSeekDirection = direction.sign;
    _edgeSeekWasPlaying = notifier.isPlaying;
    _edgeSeekBaseRate = notifier.currentPlaybackRate;
    _edgeSeekEffectiveRate = _edgeSeekBaseRate * 2;
    _edgeSeekOriginMs = notifier.currentPosition.inMilliseconds
        .toDouble()
        .clamp(0, totalMs)
        .toDouble();
    _edgeSeekTargetMs = _edgeSeekOriginMs;
    _edgeSeekStopwatch = Stopwatch()..start();
    setState(() => _isDraggingSeek = false);
    _seekPosition.value = _edgeSeekTargetMs;
    unawaited(HapticFeedback.mediumImpact());
    _edgePlaybackSetup = _startEdgePlayback(notifier);
    _tickEdgeSeek(notifier);
    _edgeSeekTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _tickEdgeSeek(notifier),
    );
  }

  Future<void> _startEdgePlayback(PlaylistContentNotifier notifier) async {
    // A paused track remains paused and is seeked once on release. When the
    // track is playing, mpv performs the accelerated playback itself so the
    // user hears the scan instead of seeing only a moving progress preview.
    if (!_edgeSeekWasPlaying || _edgeSeekDirection == 0) return;
    final direction = _edgeSeekDirection < 0 ? 'backward' : 'forward';
    final effectiveRate = _edgeSeekEffectiveRate;
    await notifier.mediaPlayer.setRawProperty('play-direction', direction);
    await notifier.mediaPlayer.setRate(effectiveRate);
    await notifier.play();
  }

  void _tickEdgeSeek(PlaylistContentNotifier notifier) {
    if (!mounted || _edgeSeekDirection == 0) return;
    final totalMs = notifier.totalDuration.inMilliseconds.toDouble();
    if (totalMs <= 0) return;

    final elapsedMs = _edgeSeekStopwatch?.elapsedMilliseconds ?? 0;
    final targetMs =
        (_edgeSeekOriginMs +
                (_edgeSeekDirection * elapsedMs * _edgeSeekEffectiveRate))
            .clamp(0, totalMs)
            .toDouble();
    if ((targetMs - _edgeSeekTargetMs).abs() < 40) return;
    _edgeSeekTargetMs = targetMs;
    _seekPosition.value = targetMs;

    if (targetMs <= 0 || targetMs >= totalMs) {
      _edgeSeekTimer?.cancel();
    }
  }

  Future<void> _stopEdgeSeek(PlaylistContentNotifier notifier) async {
    if (_edgeSeekDirection == 0) return;
    final sessionId = _seekSessionId;
    _edgeSeekTimer?.cancel();
    _edgeSeekStopwatch?.stop();
    _tickEdgeSeek(notifier);
    final targetMs = _edgeSeekTargetMs;
    final shouldResume = _edgeSeekWasPlaying;
    final baseRate = _edgeSeekBaseRate;
    final setup = _edgePlaybackSetup;
    if (mounted) {
      setState(() {
        _edgeSeekDirection = 0;
        _edgeSeekWasPlaying = false;
        _edgePlaybackSetup = null;
      });
    } else {
      _edgeSeekDirection = 0;
      _edgeSeekWasPlaying = false;
      _edgePlaybackSetup = null;
    }
    _seekPosition.value = targetMs;

    if (!mounted || sessionId != _seekSessionId) return;
    try {
      await setup;
    } catch (_) {
      // The final seek below remains available as a safe fallback on files
      // whose codec does not support mpv's reverse playback path.
    }
    if (!mounted || sessionId != _seekSessionId) return;
    try {
      await notifier.mediaPlayer.setRawProperty('play-direction', 'forward');
      await notifier.mediaPlayer.setRate(baseRate);
    } catch (_) {
      // Even if direction control is unavailable, restore the user's rate and
      // still commit the calculated position below.
      await notifier.mediaPlayer.setRate(baseRate);
    }
    if (!mounted || sessionId != _seekSessionId) return;
    await notifier.mediaPlayer.seek(Duration(milliseconds: targetMs.round()));
    if (!mounted || sessionId != _seekSessionId) return;
    // 某些 Android 音频后端在 seek 后会把 playWhenReady 留在暂停态。
    // 操作前正在播放时显式重发播放命令；原本暂停则不改变状态。
    if (shouldResume) {
      await notifier.play();
      if (!mounted || sessionId != _seekSessionId) return;
    }
    _waitForSeekPosition(notifier, sessionId, targetMs);
  }

  void _beginSeek(double value) {
    _seekSettleTimer?.cancel();
    _seekSessionId++;
    _isDraggingSeek = true;
    _seekPosition.value = value;
  }

  void _updateSeek(double value) {
    if (!_isDraggingSeek) return;
    _seekPosition.value = value;
  }

  Future<void> _commitSeek(
    double value,
    PlaylistContentNotifier notifier,
  ) async {
    final sessionId = _seekSessionId;
    _isDraggingSeek = false;
    _seekPosition.value = value;

    if (_showLyrics && notifier.currentLyrics.isNotEmpty) {
      _lyricsListController.settleOn(Duration(milliseconds: value.round()));
    }

    await notifier.mediaPlayer.seek(Duration(milliseconds: value.round()));
    if (!mounted || sessionId != _seekSessionId) return;
    _waitForSeekPosition(notifier, sessionId, value);
  }

  void _waitForSeekPosition(
    PlaylistContentNotifier notifier,
    int sessionId,
    double targetMs, [
    int attempt = 0,
  ]) {
    _seekSettleTimer?.cancel();
    _seekSettleTimer = Timer(const Duration(milliseconds: 50), () {
      if (!mounted || sessionId != _seekSessionId || _isDraggingSeek) return;

      final actualMs = notifier.currentPosition.inMilliseconds.toDouble();
      final hasCaughtUp = (actualMs - targetMs).abs() <= 750;
      final timedOutWhilePlaying = notifier.isPlaying && attempt >= 30;
      if (hasCaughtUp || timedOutWhilePlaying) {
        _seekPosition.value = null;
        return;
      }

      _waitForSeekPosition(notifier, sessionId, targetMs, attempt + 1);
    });
  }

  void _resetSeekTracking({bool deferPositionReset = false}) {
    final sessionId = ++_seekSessionId;
    _seekSettleTimer?.cancel();
    _edgeSeekTimer?.cancel();
    _edgeSeekStopwatch?.stop();
    _edgeSeekDirection = 0;
    _edgeSeekWasPlaying = false;
    _edgePlaybackSetup = null;
    _isDraggingSeek = false;
    if (deferPositionReset && _seekPosition.value != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && sessionId == _seekSessionId) {
          _seekPosition.value = null;
        }
      });
    } else {
      _seekPosition.value = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final settings = context.watch<SettingsProvider>();
    final forceDarkPlaybackTheme = shouldForceDarkPlaybackTheme(
      customBackgroundActive: _hasCustomPlaybackTheme(settings),
      followAlbumArtEnabled: settings.followAlbumArtOnPlayback,
    );
    if (!forceDarkPlaybackTheme) {
      return _buildNowPlayingPage(
        context,
        lyricFontFamily: themeProvider.currentFontFamily,
      );
    }
    return Theme(
      data: themeProvider.darkThemeData,
      child: Builder(
        builder: (darkContext) => _buildNowPlayingPage(
          darkContext,
          lyricFontFamily: themeProvider.currentFontFamily,
        ),
      ),
    );
  }

  Widget _buildNowPlayingPage(
    BuildContext context, {
    required String? lyricFontFamily,
  }) {
    final playback = context
        .select<
          PlaylistContentNotifier,
          ({
            Song? song,
            List<LyricLine> lyrics,
            Duration totalDuration,
            bool isPlaying,
            bool isFavorite,
            PlayMode playMode,
            String equalizerPreset,
            double playbackRate,
            Uint8List? cover,
          })
        >((notifier) {
          final song = notifier.currentSong;
          return (
            song: song,
            lyrics: notifier.currentLyrics,
            totalDuration: notifier.totalDuration,
            isPlaying: notifier.isPlaying,
            isFavorite: song != null && notifier.isFavorite(song),
            playMode: notifier.playMode,
            equalizerPreset: notifier.equalizerPresetName,
            playbackRate: notifier.currentPlaybackRate,
            cover: song == null ? null : notifier.displayCoverForSong(song),
          );
        });
    final notifier = context.read<PlaylistContentNotifier>();
    final settings = context.watch<SettingsProvider>();
    final song = playback.song;
    final useCustomPlaybackTheme = _hasCustomPlaybackTheme(settings);
    if (song == null) {
      return const Scaffold(body: Center(child: Text('尚未播放歌曲')));
    }
    _syncPlaybackCoverListenable(notifier, song.normalizedPath);
    final currentAlbumArt = _stabilizePlaybackCover(
      notifier: notifier,
      songPath: song.normalizedPath,
      currentCover: playback.cover,
      retainedCover: _retainedPlaybackArtworkFor(song.normalizedPath),
    );
    final useAlbumArtOnPlayback =
        settings.followAlbumArtOnPlayback && currentAlbumArt != null;
    final usePlaybackTheme = useCustomPlaybackTheme || useAlbumArtOnPlayback;
    final playbackBackground = _resolvePlaybackBackground(
      _PlaybackBackgroundFrame(
        path: settings.playbackThemeImagePath,
        customImageEnabled: useCustomPlaybackTheme,
        customImageDim: settings.playbackThemeImageDim,
        customImageBlur: settings.playbackThemeImageBlur,
        coverBytes: currentAlbumArt,
        coverEnabled: useAlbumArtOnPlayback,
        coverDim: settings.playbackAlbumArtBackgroundDim,
        coverBlur: settings.playbackAlbumArtBackgroundBlur,
        usePlaybackTheme: usePlaybackTheme,
      ),
    );
    final renderedPlaybackTheme = playbackBackground.usePlaybackTheme;
    if (_lastSongPath != song.filePath) {
      _lastSongPath = song.filePath;
      _lyricsEntryRevision++;
      _resetSeekTracking(deferPositionReset: true);
      // The setting is read once when this route is created. Previous/next
      // inside the route keeps the user's current cover/lyrics choice. Once
      // the route is popped, a new state reads the configured default again.
    }

    final totalMs = playback.totalDuration.inMilliseconds.toDouble();

    final mediaSize = MediaQuery.sizeOf(context);
    final isTablet = mediaSize.shortestSide >= 600;
    final useSplitLayout = isTablet && mediaSize.width >= 840;
    final visual = _buildNowPlayingVisual(
      context,
      notifier: notifier,
      settings: settings,
      song: song,
      lyrics: playback.lyrics,
      lyricFontFamily: lyricFontFamily,
      usePlaybackTheme: renderedPlaybackTheme,
      maxCoverSize: useSplitLayout
          ? 520
          : isTablet
          ? 400
          : 360,
    );
    final controls = _buildNowPlayingControls(
      context,
      notifier: notifier,
      settings: settings,
      song: song,
      totalMs: totalMs,
      tablet: isTablet,
      usePlaybackTheme: renderedPlaybackTheme,
    );

    final scaffold = Scaffold(
      backgroundColor: renderedPlaybackTheme ? Colors.transparent : null,
      appBar: AppBar(
        backgroundColor: renderedPlaybackTheme ? Colors.transparent : null,
        scrolledUnderElevation: renderedPlaybackTheme ? 0 : null,
        title: PlaybackProgressHeader(
          positionListenable: notifier.positionListenable,
          previewPositionListenable: _seekPosition,
          totalDuration: playback.totalDuration,
        ),
        actions: [
          IconButton(
            tooltip: '歌曲详情',
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showSongDetails(context, notifier, song),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                isTablet ? 28 : 16,
                isTablet ? 20 : 8,
                isTablet ? 28 : 16,
                isTablet ? 22 : 12,
              ),
              child: useSplitLayout
                  ? Row(
                      children: [
                        Expanded(flex: 6, child: visual),
                        const SizedBox(width: 32),
                        Expanded(
                          flex: 5,
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 480),
                              child: Card(
                                elevation: 0,
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerLow
                                    .withValues(
                                      alpha: renderedPlaybackTheme ? 0.10 : 1,
                                    ),
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: controls,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        Expanded(child: visual),
                        const SizedBox(height: 16),
                        if (isTablet)
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 560),
                            child: Card(
                              elevation: 0,
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerLow
                                  .withValues(
                                    alpha: renderedPlaybackTheme ? 0.10 : 1,
                                  ),
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: controls,
                              ),
                            ),
                          )
                        else
                          controls,
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
    return CustomThemeBackground(
      path: playbackBackground.path,
      enabled: playbackBackground.customImageEnabled,
      dim: playbackBackground.customImageDim,
      blurSigma: playbackBackground.customImageBlur,
      coverBytes: playbackBackground.coverBytes,
      coverEnabled: playbackBackground.coverEnabled,
      coverDim: playbackBackground.coverDim,
      coverBlurSigma: playbackBackground.coverBlur,
      brightnessOverride: renderedPlaybackTheme ? Brightness.dark : null,
      child: scaffold,
    );
  }

  Uint8List? _stabilizePlaybackCover({
    required PlaylistContentNotifier notifier,
    required String songPath,
    required Uint8List? currentCover,
    required Uint8List? retainedCover,
  }) {
    if (currentCover != null && currentCover.isNotEmpty) {
      _stablePlaybackCover = currentCover;
      _stablePlaybackCoverPath = songPath;
      return currentCover;
    }

    if (notifier.artworkResolutionStateForPath(songPath) ==
        ArtworkResolutionState.unavailable) {
      _stablePlaybackCover = null;
      _stablePlaybackCoverPath = null;
      return null;
    }

    // Retain the last complete frame only while the new cover is unresolved.
    // It must not be marked as the new song's stable cover, otherwise a failed
    // or delayed load can leave the previous song's background on screen.
    if (_stablePlaybackCoverPath == songPath) return _stablePlaybackCover;
    return retainedCover;
  }

  Uint8List? _retainedPlaybackArtworkFor(String songPath) {
    final current = _preparedPlaybackArtwork;
    if (current?.path == songPath) return current!.bytes;
    final previous = _previousPreparedPlaybackArtwork;
    if (previous?.path == songPath) return previous!.bytes;
    if (_playbackArtworkHandoffTargetPath != songPath) return null;
    // A newly-created route may bridge one already-decoded frame, but only
    // while the coordinator's bounded handoff still targets this song.
    return current?.bytes ?? previous?.bytes;
  }

  Widget _buildNowPlayingVisual(
    BuildContext context, {
    required PlaylistContentNotifier notifier,
    required SettingsProvider settings,
    required Song song,
    required List<LyricLine> lyrics,
    required String? lyricFontFamily,
    required bool usePlaybackTheme,
    required double maxCoverSize,
  }) {
    final activeLyricColor = context.watch<ThemeProvider>().currentSeedColor;
    Widget buildLyricsList(int activeLyric) => MobileLyricsList(
      controller: _lyricsListController,
      lines: lyrics,
      active: activeLyric,
      contentIdentity: song.normalizedPath,
      activeColor: activeLyricColor,
      position: notifier.currentPosition,
      positionListenable: _lyricsRealtimeVisualsEnabled
          ? notifier.positionListenable
          : null,
      fontSize: settings.fontSize,
      fontFamily: lyricFontFamily,
      fontWeight: settings.lyricFontWeight,
      textAlign: settings.lyricAlignment,
      elasticScrollEnabled: settings.enableLyricElasticScroll,
      lineBlurEnabled: settings.enableLyricBlur,
      highlightActiveLine: settings.highlightActiveLyric,
      isPlaying: _lyricsRealtimeVisualsEnabled && notifier.isPlaying,
      edgeFadeEnabled: true,
      glowEnabled: settings.playbackLyricGlowEnabled,
      glowRadius: settings.playbackLyricGlowRadius,
      brightForeground: usePlaybackTheme,
      onBrowseTargetSelected: (target) =>
          unawaited(_seekToBrowsedLyric(target, notifier)),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        _lyricBrowseTapHandled =
            _showLyrics &&
            _lyricsListController.isBrowseTargetAtGlobalPosition(
              details.globalPosition,
            );
      },
      onTapCancel: () => _lyricBrowseTapHandled = false,
      onTap: () {
        if (_lyricBrowseTapHandled) {
          _lyricBrowseTapHandled = false;
          _lyricsListController.selectBrowseTarget();
          return;
        }
        final showLyrics = !_showLyrics;
        final entryRevision = ++_lyricsEntryRevision;
        _frozenLyricLineIndex.value = notifier.lyricLineIndexListenable.value;
        setState(() {
          _showLyrics = showLyrics;
          _lyricsRealtimeVisualsEnabled = false;
          if (showLyrics) {
            _lyricsLayerBuilt = true;
          } else {
            _coverLayerBuilt = true;
          }
        });
        if (showLyrics) {
          // Center the retained lyric list while it is still fully transparent,
          // then start the visual transition on the next frame. This keeps the
          // expensive positioned-list jump out of the animation's first frame.
          _lyricsListController.recenter();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted ||
                !_showLyrics ||
                entryRevision != _lyricsEntryRevision) {
              return;
            }
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted ||
                  !_showLyrics ||
                  entryRevision != _lyricsEntryRevision) {
                return;
              }
              _runVisualTransition(showLyrics: true);
            });
            WidgetsBinding.instance.scheduleFrame();
          });
        } else {
          _runVisualTransition(showLyrics: false);
        }
        if (showLyrics) {
          if (!settings.preferExternalLyrics && settings.enableOnlineLyrics) {
            unawaited(notifier.refreshCurrentNetworkLyrics());
          } else if (notifier.currentLyrics.isEmpty) {
            unawaited(notifier.refreshCurrentLyricsIfEmpty());
          }
        }
      },
      onLongPressStart: !_showLyrics
          ? null
          : (details) {
              if (_lyricPointers.length > 1 || _lyricCopyGestureTriggered) {
                return;
              }
              final visualWidth = MediaQuery.sizeOf(context).width;
              final edgeWidth = (visualWidth * .16)
                  .clamp(58.0, 108.0)
                  .toDouble();
              if (details.localPosition.dx <= edgeWidth) {
                _startEdgeSeek(-1, notifier);
              } else if (details.localPosition.dx >= visualWidth - edgeWidth) {
                _startEdgeSeek(1, notifier);
              } else {
                _showLyricsFontSizeSheet(context, settings);
              }
            },
      onLongPressEnd: !_showLyrics
          ? null
          : (_) => unawaited(_stopEdgeSeek(notifier)),
      onLongPressCancel: !_showLyrics
          ? null
          : () => unawaited(_stopEdgeSeek(notifier)),
      child: Listener(
        onPointerDown: _showLyrics ? _onLyricPointerDown : null,
        onPointerMove: _showLyrics ? _onLyricPointerMove : null,
        onPointerUp: _showLyrics
            ? (event) => _onLyricPointerEnd(event, settings)
            : null,
        onPointerCancel: _showLyrics
            ? (event) => _onLyricPointerEnd(event, settings)
            : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_coverLayerBuilt)
              IgnorePointer(
                ignoring: _showLyrics,
                child: ExcludeSemantics(
                  excluding: _showLyrics,
                  child: AnimatedBuilder(
                    animation: _coverTransitionController,
                    builder: (context, child) {
                      final progress = _coverTransitionController.value;
                      final opacity = 1 - (progress / 0.74).clamp(0.0, 1.0);
                      return Opacity(
                        opacity: opacity,
                        child: Transform.scale(
                          scale: 1 - 0.08 * progress,
                          alignment: Alignment.center,
                          child: child,
                        ),
                      );
                    },
                    child: RepaintBoundary(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final size = constraints.biggest.shortestSide
                              .clamp(180.0, maxCoverSize)
                              .toDouble();
                          return Center(
                            child: GestureDetector(
                              onLongPress: () => _showSongCoverActions(
                                context,
                                notifier,
                                song,
                              ),
                              child: NowPlayingCoverHero(
                                normalizedSongPath: song.normalizedPath,
                                enabled: shouldEnableNowPlayingCoverHero(
                                  showLyrics: _showLyrics,
                                  routeTransitionComplete:
                                      _routeTransitionComplete,
                                  initialCoverHeroReady:
                                      widget.initialCoverHeroReady,
                                ),
                                child: _AtomicNowPlayingCover(
                                  songPath: song.normalizedPath,
                                  size: size,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            if (_lyricsLayerBuilt)
              IgnorePointer(
                ignoring: !_showLyrics,
                child: ExcludeSemantics(
                  excluding: !_showLyrics,
                  child: AnimatedBuilder(
                    animation: _lyricsContentTransitionController,
                    builder: (context, child) {
                      final progress = _lyricsContentTransitionController.value;
                      return Opacity(
                        opacity: progress,
                        child: Transform.scale(
                          scale: 0.98 + 0.02 * progress,
                          alignment: Alignment.center,
                          child: child,
                        ),
                      );
                    },
                    child: TickerMode(
                      enabled: _lyricsRealtimeVisualsEnabled,
                      child: RepaintBoundary(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          // Keep one stable bridge around the lyric list. A
                          // conditional wrapper used to replace the complete
                          // list subtree when realtime visuals were paused,
                          // forcing every highlighted line and cached glyph
                          // layer to be recreated inside the page transition.
                          child: ValueListenableBuilder<int>(
                            key: const ValueKey(
                              'now_playing_lyric_index_bridge',
                            ),
                            valueListenable: _lyricsRealtimeVisualsEnabled
                                ? notifier.lyricLineIndexListenable
                                : _frozenLyricLineIndex,
                            builder: (context, activeLyric, _) =>
                                buildLyricsList(activeLyric),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_showLyrics && _edgeSeekDirection != 0)
              LayoutBuilder(
                builder: (context, constraints) {
                  final edgeWidth = (constraints.maxWidth * .16)
                      .clamp(58.0, 108.0)
                      .toDouble();
                  return Stack(
                    children: [
                      _buildLyricsEdgeSeekZone(
                        context,
                        notifier: notifier,
                        direction: -1,
                        width: edgeWidth,
                      ),
                      _buildLyricsEdgeSeekZone(
                        context,
                        notifier: notifier,
                        direction: 1,
                        width: edgeWidth,
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLyricsEdgeSeekZone(
    BuildContext context, {
    required PlaylistContentNotifier notifier,
    required int direction,
    required double width,
  }) {
    final isActive = _edgeSeekDirection == direction;
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned(
      top: 0,
      bottom: 0,
      left: direction < 0 ? 0 : null,
      right: direction > 0 ? 0 : null,
      width: width,
      child: IgnorePointer(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: isActive
                ? colorScheme.primaryContainer.withValues(alpha: .34)
                : Colors.transparent,
            borderRadius: BorderRadius.horizontal(
              left: direction > 0 ? const Radius.circular(24) : Radius.zero,
              right: direction < 0 ? const Radius.circular(24) : Radius.zero,
            ),
          ),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 120),
            opacity: isActive ? 1 : 0,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    direction < 0 ? Icons.fast_rewind : Icons.fast_forward,
                    color: colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(notifier.currentPlaybackRate * 2).toStringAsFixed(2)}×',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNowPlayingControls(
    BuildContext context, {
    required PlaylistContentNotifier notifier,
    required SettingsProvider settings,
    required Song song,
    required double totalMs,
    required bool tablet,
    required bool usePlaybackTheme,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final timelineControls = ValueListenableBuilder<double?>(
      valueListenable: _seekPosition,
      builder: (context, seekPosition, _) => ValueListenableBuilder<Duration>(
        valueListenable: notifier.positionListenable,
        builder: (context, position, _) {
          final playerPosition = position.inMilliseconds
              .toDouble()
              .clamp(0, totalMs > 0 ? totalMs : 1)
              .toDouble();
          final displayPosition = (seekPosition ?? playerPosition)
              .clamp(0, totalMs > 0 ? totalMs : 1)
              .toDouble();
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: tablet ? 42 : 34,
                child: Slider(
                  value: displayPosition,
                  max: totalMs > 0 ? totalMs : 1,
                  onChangeStart: _beginSeek,
                  onChanged: _updateSeek,
                  onChangeEnd: (value) => _commitSeek(value, notifier),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _duration(
                        Duration(milliseconds: displayPosition.round()),
                      ),
                    ),
                    Text(_duration(notifier.totalDuration)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
    final transportControls = SizedBox(
      height: tablet ? 80 : 72,
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: IconButton(
                tooltip: notifier.isFavorite(song) ? '取消收藏' : '收藏',
                icon: Icon(
                  notifier.isFavorite(song)
                      ? Icons.favorite
                      : Icons.favorite_border,
                ),
                color: notifier.isFavorite(song) ? colorScheme.primary : null,
                onPressed: () => notifier.toggleFavorite(song),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: IconButton(
                tooltip: '上一首',
                icon: const Icon(Icons.skip_previous, size: 38),
                onPressed: () {
                  _resetSeekTracking();
                  notifier.playPrevious();
                },
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: PlayPauseButton(
                isPlaying: notifier.isPlaying,
                size: 42,
                padding: const EdgeInsets.all(8),
                tooltip: notifier.isPlaying ? '暂停' : '播放',
                color: colorScheme.onSurface,
                onPressed: () {
                  if (notifier.isPlaying) {
                    notifier.pause();
                  } else {
                    _resetSeekTracking();
                    notifier.play();
                  }
                },
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: IconButton(
                tooltip: '下一首',
                icon: const Icon(Icons.skip_next, size: 38),
                onPressed: () {
                  _resetSeekTracking();
                  notifier.playNext();
                },
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: IconButton(
                tooltip: _modeLabel(notifier.playMode),
                icon: Icon(_modeIcon(notifier.playMode), size: 28),
                onPressed: notifier.togglePlayMode,
              ),
            ),
          ),
        ],
      ),
    );
    final primaryControls = usePlaybackTheme
        ? _playbackThemePanel(
            context,
            enabled: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  timelineControls,
                  SizedBox(height: tablet ? 6 : 0),
                  transportControls,
                ],
              ),
            ),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              timelineControls,
              SizedBox(height: tablet ? 4 : 0),
              transportControls,
            ],
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: tablet ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: tablet
                        ? Theme.of(context).textTheme.headlineSmall
                        : Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _buildEqualizerPresetButton(
              context,
              notifier: notifier,
              usePlaybackTheme: usePlaybackTheme,
            ),
          ],
        ),
        SizedBox(height: tablet ? 10 : 4),
        primaryControls,
        SizedBox(height: tablet ? 12 : 10),
        _playbackThemePanel(
          context,
          enabled: usePlaybackTheme,
          child: Material(
            color: usePlaybackTheme
                ? Colors.transparent
                : Theme.of(context).colorScheme.surfaceContainer,
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                Expanded(
                  child: IconButton(
                    tooltip: '歌词源',
                    icon: const Icon(Icons.lyrics_outlined),
                    onPressed: () => _showLyricSource(context),
                  ),
                ),
                const SizedBox(height: 30, child: VerticalDivider(width: 1)),
                Expanded(
                  child: IconButton(
                    tooltip: '歌曲列表',
                    icon: const Icon(Icons.queue_music),
                    onPressed: () => _showQueue(context),
                  ),
                ),
                const SizedBox(height: 30, child: VerticalDivider(width: 1)),
                Expanded(
                  child: IconButton(
                    tooltip: '音频效果',
                    icon: const Icon(Icons.tune),
                    onPressed: () => _showAudioEffects(context),
                  ),
                ),
                if (settings.showAudioAnalysis) ...[
                  const SizedBox(height: 30, child: VerticalDivider(width: 1)),
                  Expanded(
                    child: IconButton(
                      tooltip: '音频分析',
                      icon: const Icon(Icons.graphic_eq),
                      onPressed: () => Navigator.of(context).push(
                        CupertinoPageRoute<void>(
                          builder: (_) => const AudioAnalysisPage(),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEqualizerPresetButton(
    BuildContext context, {
    required PlaylistContentNotifier notifier,
    required bool usePlaybackTheme,
  }) {
    if (!usePlaybackTheme) {
      return ActionChip(
        avatar: const Icon(Icons.equalizer, size: 18),
        label: Text(notifier.equalizerPresetName),
        onPressed: () => _showPresetPicker(context, notifier),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final brightForeground = Theme.of(context).brightness == Brightness.light;
    final labelColor = brightForeground ? Colors.white : scheme.onSurface;
    final borderColor = brightForeground
        ? Colors.white.withValues(alpha: .82)
        : scheme.outline;
    final radius = BorderRadius.circular(14);
    return _playbackThemePanel(
      context,
      enabled: true,
      borderRadius: radius,
      drawBorder: false,
      child: Semantics(
        button: true,
        label: '均衡器预设：${notifier.equalizerPresetName}',
        child: InkWell(
          borderRadius: radius,
          onTap: () => _showPresetPicker(context, notifier),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: borderColor),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.equalizer, size: 18, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      notifier.equalizerPresetName,
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(color: labelColor),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _playbackThemePanel(
    BuildContext context, {
    required bool enabled,
    required Widget child,
    BorderRadius? borderRadius,
    bool drawBorder = true,
  }) {
    if (!enabled) return child;
    final scheme = Theme.of(context).colorScheme;
    final borderColor = Theme.of(context).brightness == Brightness.light
        ? Colors.white.withValues(alpha: _playbackGlassBorderAlpha)
        : scheme.outlineVariant.withValues(alpha: _playbackGlassBorderAlpha);
    final radius = borderRadius ?? BorderRadius.circular(22);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: _playbackGlassBlur,
          sigmaY: _playbackGlassBlur,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: _playbackGlassFillAlpha),
            borderRadius: radius,
            border: drawBorder ? Border.all(color: borderColor) : null,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        ),
      ),
    );
  }

  Future<void> _showLyricsFontSizeSheet(
    BuildContext context,
    SettingsProvider settings,
  ) async {
    final usePlaybackTheme = _hasResolvedPlaybackTheme(
      settings,
      context.read<PlaylistContentNotifier>(),
    );
    double currentSize = settings.fontSize;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: !usePlaybackTheme,
      backgroundColor: usePlaybackTheme ? Colors.transparent : null,
      shape: usePlaybackTheme ? _playbackSheetShape(context) : null,
      clipBehavior: usePlaybackTheme ? Clip.antiAlias : Clip.none,
      builder: (sheetContext) {
        final content = SafeArea(
          child: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setSheetState) => Padding(
                padding: EdgeInsets.fromLTRB(
                  24,
                  usePlaybackTheme ? 16 : 4,
                  24,
                  20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '歌词字体大小',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: '恢复默认大小',
                          icon: const Icon(Icons.restart_alt),
                          onPressed: () {
                            const value = SettingsProvider.defaultLyricFontSize;
                            setSheetState(() => currentSize = value);
                            settings.setFontSize(value);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Slider(
                      value: currentSize,
                      min: 12,
                      max: 32,
                      divisions: 20,
                      label: currentSize.toStringAsFixed(0),
                      onChanged: (value) {
                        setSheetState(() => currentSize = value);
                        settings.setFontSize(value);
                      },
                    ),
                    Text(
                      '当前大小: ${currentSize.toStringAsFixed(1)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Divider(height: 32),
                    _SleepTimerSection(
                      notifier: context.read<PlaylistContentNotifier>(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        return usePlaybackTheme
            ? _playbackThemeSheetSurface(sheetContext, child: content)
            : content;
      },
    );
  }

  void _onLyricPointerDown(PointerDownEvent event) {
    _lyricPointers[event.pointer] = event.localPosition;
    _lyricPointerOrigins[event.pointer] = event.localPosition;
    if (_lyricPointers.length == 2) {
      final points = _lyricPointers.values.toList(growable: false);
      _lyricPinchStartDistance = (points[0] - points[1]).distance;
      _lyricPinchStartFontSize = context.read<SettingsProvider>().fontSize;
      _lyricCopyGestureTriggered = false;
      _lyricCopyHoldTimer?.cancel();
      if (_edgeSeekDirection != 0) return;
      _lyricCopyHoldTimer = Timer(const Duration(milliseconds: 650), () {
        if (!mounted || !_showLyrics || _lyricPointers.length != 2) return;
        final originalFontSize = _lyricPinchStartFontSize;
        if (originalFontSize != null) {
          context.read<SettingsProvider>().previewFontSize(originalFontSize);
        }
        _lyricCopyGestureTriggered = true;
        _lyricPinchStartDistance = null;
        _lyricPinchStartFontSize = null;
        unawaited(HapticFeedback.mediumImpact());
        unawaited(_showLyricCopyOptions());
      });
    } else if (_lyricPointers.length > 2) {
      _lyricCopyHoldTimer?.cancel();
    }
  }

  void _onLyricPointerMove(PointerMoveEvent event) {
    if (!_lyricPointers.containsKey(event.pointer)) return;
    _lyricPointers[event.pointer] = event.localPosition;
    final origin = _lyricPointerOrigins[event.pointer];
    if (origin != null && (event.localPosition - origin).distance > 12) {
      _lyricCopyHoldTimer?.cancel();
    }
    if (_lyricPointers.length != 2 ||
        _lyricPinchStartDistance == null ||
        _lyricPinchStartFontSize == null) {
      return;
    }
    final points = _lyricPointers.values.toList(growable: false);
    final distance = (points[0] - points[1]).distance;
    if (_lyricPinchStartDistance! > 0) {
      final scale = distance / _lyricPinchStartDistance!;
      if ((scale - 1).abs() > .04) _lyricCopyHoldTimer?.cancel();
      final target = (_lyricPinchStartFontSize! * scale).clamp(12.0, 32.0);
      context.read<SettingsProvider>().previewFontSize(target);
    }
  }

  void _onLyricPointerEnd(PointerEvent event, SettingsProvider settings) {
    _lyricCopyHoldTimer?.cancel();
    if (_lyricPinchStartDistance != null && !_lyricCopyGestureTriggered) {
      settings.setFontSize(settings.fontSize);
    }
    _lyricPointers.remove(event.pointer);
    _lyricPointerOrigins.remove(event.pointer);
    if (_lyricPointers.length < 2) {
      _lyricPinchStartDistance = null;
      _lyricPinchStartFontSize = null;
    }
    if (_lyricPointers.isEmpty) _lyricCopyGestureTriggered = false;
  }

  Future<void> _showLyricCopyOptions() async {
    final notifier = context.read<PlaylistContentNotifier>();
    if (notifier.currentLyrics.isEmpty) return;
    final lines = List<LyricLine>.unmodifiable(notifier.currentLyrics);
    final activeLineIndex = notifier.currentLyricLineIndex;
    final fontFamily = context.read<ThemeProvider>().currentFontFamily;
    final usePlaybackTheme = _hasResolvedPlaybackTheme(
      context.read<SettingsProvider>(),
      notifier,
    );
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: usePlaybackTheme ? Colors.transparent : null,
      shape: usePlaybackTheme ? _playbackSheetShape(context) : null,
      clipBehavior: usePlaybackTheme ? Clip.antiAlias : Clip.none,
      builder: (sheetContext) {
        final content = SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.copy_all_outlined),
                title: const Text('复制完整歌词'),
                onTap: () => Navigator.pop(sheetContext, 'all'),
              ),
              ListTile(
                leading: const Icon(Icons.checklist_outlined),
                title: const Text('仅复制部分歌词'),
                onTap: () => Navigator.pop(sheetContext, 'partial'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
        return usePlaybackTheme
            ? _playbackThemeSheetSurface(sheetContext, child: content)
            : content;
      },
    );
    if (!mounted || choice == null) return;
    if (choice == 'all') {
      final text = lyricsClipboardText(lines);
      if (text.isEmpty) return;
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        context.read<NotificationService>().success('已复制完整歌词');
      }
      return;
    }
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => LyricCopyPage(
          lines: lines,
          activeLineIndex: activeLineIndex,
          fontFamily: fontFamily,
        ),
      ),
    );
  }

  void _showQueue(BuildContext context) {
    final usePlaybackTheme = _hasResolvedPlaybackTheme(
      context.read<SettingsProvider>(),
      context.read<PlaylistContentNotifier>(),
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: usePlaybackTheme ? Colors.transparent : null,
      shape: usePlaybackTheme ? _playbackSheetShape(context) : null,
      clipBehavior: usePlaybackTheme ? Clip.antiAlias : Clip.none,
      builder: (sheetContext) {
        final content = FractionallySizedBox(
          heightFactor: .82,
          child: PlayingQueueDrawer(
            transparentBackground: usePlaybackTheme,
            syncHomeBackground: false,
          ),
        );
        return usePlaybackTheme
            ? _playbackThemeSheetSurface(sheetContext, child: content)
            : content;
      },
    );
  }

  void _showPresetPicker(
    BuildContext context,
    PlaylistContentNotifier notifier,
  ) {
    final usePlaybackTheme = _hasResolvedPlaybackTheme(
      context.read<SettingsProvider>(),
      notifier,
    );
    var pitch = notifier.currentPitch;
    var playbackRate = notifier.currentPlaybackRate;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: usePlaybackTheme ? Colors.transparent : null,
      shape: usePlaybackTheme ? _playbackSheetShape(context) : null,
      clipBehavior: usePlaybackTheme ? Clip.antiAlias : Clip.none,
      builder: (sheetContext) {
        final content = SafeArea(
          child: StatefulBuilder(
            builder: (context, setSheetState) => Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('均衡器预设', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: PlaylistContentNotifier.equalizerPresets
                        .skip(1)
                        .map(
                          (preset) => TransparentChipSurface(
                            enabled: usePlaybackTheme,
                            child: ChoiceChip(
                              label: Text(preset.name),
                              selected:
                                  preset.name == notifier.equalizerPresetName,
                              backgroundColor: usePlaybackTheme
                                  ? Colors.transparent
                                  : null,
                              selectedColor: usePlaybackTheme
                                  ? Colors.transparent
                                  : null,
                              side: usePlaybackTheme
                                  ? BorderSide(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outline,
                                    )
                                  : null,
                              onSelected: (_) {
                                notifier.applyEqualizerPreset(preset);
                                Navigator.pop(sheetContext);
                              },
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 18),
                  _audioControlSlider(
                    context,
                    icon: Icons.music_note,
                    label: '音高',
                    value: pitch,
                    valueLabel: pitch.toStringAsFixed(2),
                    min: .5,
                    max: 1.5,
                    divisions: 20,
                    onChanged: (value) {
                      setSheetState(() => pitch = value);
                      unawaited(notifier.setPitch(value));
                    },
                  ),
                  const SizedBox(height: 8),
                  _audioControlSlider(
                    context,
                    icon: Icons.speed,
                    label: '倍速',
                    value: playbackRate,
                    valueLabel: '${playbackRate.toStringAsFixed(2)}x',
                    min: .5,
                    max: 2,
                    divisions: 30,
                    onChanged: (value) {
                      setSheetState(() => playbackRate = value);
                      unawaited(notifier.setPlaybackRate(value));
                    },
                  ),
                ],
              ),
            ),
          ),
        );
        return usePlaybackTheme
            ? _playbackThemeSheetSurface(sheetContext, child: content)
            : content;
      },
    );
  }

  Widget _audioControlSlider(
    BuildContext context, {
    required IconData icon,
    required String label,
    required double value,
    required String valueLabel,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        SizedBox(
          width: 42,
          child: Text(label, style: Theme.of(context).textTheme.titleSmall),
        ),
        Expanded(
          child: Slider(
            min: min,
            max: max,
            divisions: divisions,
            value: value,
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 54, child: Text(valueLabel, textAlign: TextAlign.end)),
      ],
    );
  }

  void _showLyricSource(BuildContext context) {
    final usePlaybackTheme = _hasResolvedPlaybackTheme(
      context.read<SettingsProvider>(),
      context.read<PlaylistContentNotifier>(),
    );
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: false,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: usePlaybackTheme ? Colors.transparent : null,
      shape: usePlaybackTheme ? _playbackSheetShape(context) : null,
      clipBehavior: usePlaybackTheme ? Clip.antiAlias : Clip.none,
      builder: (sheetContext) {
        final content = FractionallySizedBox(
          heightFactor: .62,
          child: _LyricSettingsSheet(transparentBackground: usePlaybackTheme),
        );
        return usePlaybackTheme
            ? _playbackThemeSheetSurface(sheetContext, child: content)
            : content;
      },
    );
  }

  void _showAudioEffects(BuildContext context) {
    final usePlaybackTheme = _hasResolvedPlaybackTheme(
      context.read<SettingsProvider>(),
      context.read<PlaylistContentNotifier>(),
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 260),
        reverseDuration: Duration(milliseconds: 220),
      ),
      backgroundColor: usePlaybackTheme ? Colors.transparent : null,
      shape: usePlaybackTheme ? _playbackSheetShape(context) : null,
      clipBehavior: Clip.antiAlias,
      builder: (sheetContext) {
        final content = FractionallySizedBox(
          heightFactor: .92,
          child: RepaintBoundary(
            child: _AudioEffectsSheet(transparentBackground: usePlaybackTheme),
          ),
        );
        return usePlaybackTheme
            ? _playbackThemeSheetSurface(sheetContext, child: content)
            : content;
      },
    );
  }

  Widget _playbackThemeSheetSurface(
    BuildContext context, {
    required Widget child,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final brightForeground = Theme.of(context).brightness == Brightness.light;
    final borderColor = brightForeground
        ? Colors.white.withValues(alpha: _playbackGlassBorderAlpha)
        : scheme.outlineVariant.withValues(alpha: _playbackGlassBorderAlpha);
    final themedChild = _playbackForegroundTheme(
      context,
      enabled: brightForeground,
      child: child,
    );
    const radius = BorderRadius.vertical(top: Radius.circular(28));
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: _playbackGlassBlur,
          sigmaY: _playbackGlassBlur,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: _playbackGlassFillAlpha),
            borderRadius: radius,
            border: Border.all(color: borderColor),
          ),
          child: Material(
            color: Colors.transparent,
            shape: const RoundedRectangleBorder(borderRadius: radius),
            clipBehavior: Clip.antiAlias,
            child: themedChild,
          ),
        ),
      ),
    );
  }

  RoundedRectangleBorder _playbackSheetShape(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = theme.brightness == Brightness.light
        ? Colors.white.withValues(alpha: _playbackGlassBorderAlpha)
        : theme.colorScheme.outlineVariant;
    return RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      side: BorderSide(color: borderColor),
    );
  }

  Widget _playbackForegroundTheme(
    BuildContext context, {
    required bool enabled,
    required Widget child,
  }) {
    if (!enabled) return child;
    final theme = Theme.of(context);
    const foreground = Colors.white;
    final secondaryForeground = foreground.withValues(alpha: .82);
    final outline = foreground.withValues(alpha: .82);
    final scheme = theme.colorScheme.copyWith(
      onSurface: foreground,
      onSurfaceVariant: secondaryForeground,
      onPrimaryContainer: foreground,
      onSecondaryContainer: foreground,
      outline: outline,
      outlineVariant: foreground.withValues(alpha: .56),
    );
    return Theme(
      data: theme.copyWith(
        colorScheme: scheme,
        textTheme: theme.textTheme.apply(
          bodyColor: foreground,
          displayColor: foreground,
        ),
        primaryTextTheme: theme.primaryTextTheme.apply(
          bodyColor: foreground,
          displayColor: foreground,
        ),
        iconTheme: theme.iconTheme.copyWith(color: foreground),
        primaryIconTheme: theme.primaryIconTheme.copyWith(color: foreground),
        dividerColor: foreground.withValues(alpha: .30),
        disabledColor: foreground.withValues(alpha: .38),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: foreground),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: foreground,
            side: BorderSide(color: outline),
          ),
        ),
        listTileTheme: theme.listTileTheme.copyWith(
          textColor: foreground,
          iconColor: foreground,
        ),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: foreground),
        child: IconTheme.merge(
          data: const IconThemeData(color: foreground),
          child: child,
        ),
      ),
    );
  }

  Future<void> _showSongCoverActions(
    BuildContext context,
    PlaylistContentNotifier notifier,
    Song song,
  ) async {
    final overrides = context.read<CoverOverrideService>();
    final currentArtwork = notifier.displayCoverForSong(song);
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.queue_music),
                title: const Text('从歌曲列表选取'),
                onTap: () => Navigator.pop(sheetContext, 'songs'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('从相册选取并裁剪'),
                onTap: () => Navigator.pop(sheetContext, 'gallery'),
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('下载当前封面'),
                enabled: currentArtwork != null && currentArtwork.isNotEmpty,
                onTap: currentArtwork == null || currentArtwork.isEmpty
                    ? null
                    : () => Navigator.pop(sheetContext, 'download'),
              ),
              if (overrides.hasSongCover(song.filePath))
                ListTile(
                  leading: const Icon(Icons.restore),
                  title: const Text('重置播放器内封面'),
                  onTap: () => Navigator.pop(sheetContext, 'reset'),
                ),
              const Divider(height: 24),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                child: _SleepTimerSection(notifier: notifier),
              ),
            ],
          ),
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    if (action == 'download' && currentArtwork != null) {
      await _downloadCover(context, currentArtwork, song.title);
      return;
    }
    if (action == 'reset') {
      await overrides.setSongCover(song.filePath, null);
      if (context.mounted) {
        context.read<NotificationService>().success('已恢复文件内封面');
      }
      return;
    }

    Uint8List? selectedArtwork;
    if (action == 'gallery') {
      selectedArtwork = await _pickAndCropCover(context);
    } else if (action == 'songs') {
      selectedArtwork = await _pickCoverFromSongs(context, notifier);
    }
    if (!context.mounted || selectedArtwork == null) return;
    final target = await _chooseCoverApplyTarget(context, group: false);
    if (!context.mounted || target == null) return;
    if (target == _CoverApplyTarget.appOnly) {
      await overrides.setSongCover(song.filePath, selectedArtwork);
      if (context.mounted) {
        context.read<NotificationService>().success('播放器内封面已更换');
      }
      return;
    }
    if (!await _confirmSourceCoverWrite(context, count: 1) ||
        !context.mounted) {
      return;
    }
    try {
      await AudioCoverEditorService.replaceEmbeddedCover(
        song.filePath,
        selectedArtwork,
      );
      await overrides.setSongCover(song.filePath, null);
      await notifier.refreshSongCoverAfterFileEdit(song.filePath);
      if (context.mounted) {
        context.read<NotificationService>().success('音频文件封面已替换');
      }
    } catch (error) {
      if (context.mounted) {
        context.read<NotificationService>().error(
          '替换文件封面失败：${_coverWriteError(error)}',
        );
      }
    }
  }

  Future<Uint8List?> _pickCoverFromSongs(
    BuildContext context,
    PlaylistContentNotifier notifier,
  ) {
    final candidates = notifier.allSongs
        .where((song) => notifier.displayCoverForSong(song)?.isNotEmpty == true)
        .toList();
    return showModalBottomSheet<Uint8List>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .72,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '选择歌曲封面',
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: candidates.length,
                  itemBuilder: (_, index) {
                    final candidate = candidates[index];
                    final artwork = notifier.displayCoverForSong(candidate)!;
                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: ArtworkImage(
                          bytes: artwork,
                          size: ArtworkSize.thumbnail,
                          width: 46,
                          height: 46,
                          fit: BoxFit.cover,
                        ),
                      ),
                      title: Text(candidate.title),
                      subtitle: Text(candidate.artist),
                      onTap: () => Navigator.pop(sheetContext, artwork),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSongDetails(
    BuildContext context,
    PlaylistContentNotifier notifier,
    Song song,
  ) async {
    FileStat? stat;
    if (!song.filePath.startsWith('content://')) {
      try {
        final file = File(song.filePath);
        if (await file.exists()) stat = await file.stat();
      } catch (_) {}
    }
    if (!context.mounted) return;
    final playCount =
        context
            .read<StatisticsManager>()
            .getSongStatByPath(song.filePath)
            ?.playCount ??
        0;
    final state = notifier.mediaPlayer.state;
    final bitrate = state.audioBitrate;
    final sampleRate = state.audioParams.sampleRate;
    final duration = song.duration ?? notifier.totalDuration;
    final estimatedListening = Duration(
      milliseconds: duration.inMilliseconds * playCount,
    );
    final usePlaybackTheme = _hasResolvedPlaybackTheme(
      context.read<SettingsProvider>(),
      notifier,
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: usePlaybackTheme ? Colors.transparent : null,
      shape: usePlaybackTheme ? _playbackSheetShape(context) : null,
      clipBehavior: usePlaybackTheme ? Clip.antiAlias : Clip.none,
      builder: (sheetContext) {
        final content = DraggableScrollableSheet(
          expand: false,
          initialChildSize: .72,
          minChildSize: .45,
          maxChildSize: .92,
          builder: (context, controller) => SafeArea(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                Text('歌曲详情', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                _DetailRow(label: '歌曲名', value: song.title),
                _DetailRow(label: '歌手', value: song.artist),
                _DetailRow(label: '专辑', value: song.album),
                _DetailRow(label: '收听次数', value: '$playCount 次'),
                _DetailRow(
                  label: '累计收听时间',
                  value: '${_longDuration(estimatedListening)}（估算）',
                ),
                _DetailRow(
                  label: '比特率',
                  value: bitrate == null
                      ? '未知'
                      : '${(bitrate / 1000).round()} kbps',
                ),
                _DetailRow(
                  label: '采样率',
                  value: sampleRate == null
                      ? '未知'
                      : '${(sampleRate / 1000).toStringAsFixed(1)} kHz',
                ),
                _DetailRow(label: '时长', value: _duration(duration)),
                _DetailRow(
                  label: '创建日期',
                  value: stat == null ? '未知' : _dateTime(stat.changed),
                ),
                _DetailRow(
                  label: '修改日期',
                  value: stat == null ? '未知' : _dateTime(stat.modified),
                ),
                _DetailRow(
                  label: '文件路径',
                  value: song.filePath,
                  selectable: true,
                ),
              ],
            ),
          ),
        );
        return usePlaybackTheme
            ? _playbackThemeSheetSurface(sheetContext, child: content)
            : content;
      },
    );
  }
}

const _playbackSleepPresets = <(String, Duration)>[
  ('5分钟', Duration(minutes: 5)),
  ('10分钟', Duration(minutes: 10)),
  ('15分钟', Duration(minutes: 15)),
  ('30分钟', Duration(minutes: 30)),
  ('60分钟', Duration(hours: 1)),
  ('2小时', Duration(hours: 2)),
];

String _sleepTimerRemainingLabel(Duration remaining) {
  final seconds = remaining.inSeconds.clamp(0, 3599999);
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final trailingSeconds = seconds % 60;
  if (hours > 0) {
    return '$hours小时${minutes.toString().padLeft(2, '0')}分'
        '${trailingSeconds.toString().padLeft(2, '0')}秒';
  }
  return '$minutes分${trailingSeconds.toString().padLeft(2, '0')}秒';
}

Future<Duration?> _showCustomSleepTimerDialog(
  BuildContext context,
  Duration? current,
) async {
  final roundedMinutes = current == null
      ? 30
      : ((current.inSeconds + 59) ~/ 60).clamp(1, 59999);
  final hoursController = TextEditingController(
    text: '${roundedMinutes ~/ 60}',
  );
  final minutesController = TextEditingController(
    text: '${roundedMinutes % 60}',
  );
  String? error;
  final result = await showDialog<Duration>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('自定义播放定时'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('到达设定时长后自动暂停播放'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('sleep-timer-hours'),
                    controller: hoursController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: '小时',
                      suffixText: '时',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const ValueKey('sleep-timer-minutes'),
                    controller: minutesController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    decoration: const InputDecoration(
                      labelText: '分钟',
                      suffixText: '分',
                    ),
                  ),
                ),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final hours = int.tryParse(hoursController.text) ?? 0;
              final minutes = int.tryParse(minutesController.text) ?? 0;
              if (minutes > 59 || (hours == 0 && minutes == 0)) {
                setDialogState(() {
                  error = minutes > 59 ? '分钟请输入 0–59' : '定时时长必须大于 0';
                });
                return;
              }
              Navigator.pop(
                dialogContext,
                Duration(hours: hours, minutes: minutes),
              );
            },
            child: const Text('开始定时'),
          ),
        ],
      ),
    ),
  );
  hoursController.dispose();
  minutesController.dispose();
  return result;
}

class _SleepTimerSection extends StatefulWidget {
  const _SleepTimerSection({required this.notifier});

  final PlaylistContentNotifier notifier;

  @override
  State<_SleepTimerSection> createState() => _SleepTimerSectionState();
}

class _SleepTimerSectionState extends State<_SleepTimerSection> {
  late final Timer _clock;

  @override
  void initState() {
    super.initState();
    widget.notifier.addListener(_handleTimerChanged);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.notifier.playbackSleepTimerDeadline != null) {
        setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(_SleepTimerSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notifier == widget.notifier) return;
    oldWidget.notifier.removeListener(_handleTimerChanged);
    widget.notifier.addListener(_handleTimerChanged);
  }

  void _handleTimerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _clock.cancel();
    widget.notifier.removeListener(_handleTimerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.notifier.playbackSleepTimerRemaining;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.bedtime_outlined),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('播放定时', style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    remaining == null
                        ? '未设置，到时自动暂停播放'
                        : '剩余 ${_sleepTimerRemainingLabel(remaining)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (remaining != null)
              TextButton(
                onPressed: widget.notifier.cancelPlaybackSleepTimer,
                child: const Text('取消定时'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in _playbackSleepPresets)
              ActionChip(
                label: Text(preset.$1),
                onPressed: () =>
                    widget.notifier.setPlaybackSleepTimer(preset.$2),
              ),
            ActionChip(
              avatar: const Icon(Icons.tune, size: 18),
              label: const Text('自定义'),
              onPressed: () async {
                final duration = await _showCustomSleepTimerDialog(
                  context,
                  widget.notifier.playbackSleepTimerRemaining,
                );
                if (duration != null && mounted) {
                  widget.notifier.setPlaybackSleepTimer(duration);
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _LyricSettingsSheet extends StatefulWidget {
  const _LyricSettingsSheet({required this.transparentBackground});

  final bool transparentBackground;

  @override
  State<_LyricSettingsSheet> createState() => _LyricSettingsSheetState();
}

class _LyricSettingsSheetState extends State<_LyricSettingsSheet> {
  int _section = 0;

  static const _sections = [
    (icon: Icons.lyrics_outlined, label: '歌词设置'),
    (icon: Icons.source_outlined, label: '歌词源'),
  ];

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 68,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: widget.transparentBackground
                  ? Colors.transparent
                  : scheme.surfaceContainer,
              border: Border(right: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Column(
              children: [
                for (var index = 0; index < _sections.length; index++) ...[
                  Tooltip(
                    message: _sections[index].label,
                    child: IconButton.filledTonal(
                      key: ValueKey('lyric-settings-section-$index'),
                      isSelected: _section == index,
                      style: widget.transparentBackground
                          ? IconButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              side: BorderSide(color: scheme.outlineVariant),
                            )
                          : null,
                      selectedIcon: Icon(_sections[index].icon),
                      icon: Icon(_sections[index].icon),
                      onPressed: () => setState(() => _section = index),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _sections[_section].label,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: IndexedStack(
                    index: _section,
                    children: [
                      _lyricDisplayPage(context, settings),
                      _lyricSourcePage(context, settings),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _lyricDisplayPage(BuildContext context, SettingsProvider settings) {
    return ListView(
      key: const ValueKey('lyric-settings-display-page'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<TextAlign>(
            expandedInsets: EdgeInsets.zero,
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: TextAlign.left,
                icon: Icon(Icons.format_align_left),
                tooltip: '左对齐',
              ),
              ButtonSegment(
                value: TextAlign.center,
                icon: Icon(Icons.format_align_center),
                tooltip: '居中',
              ),
              ButtonSegment(
                value: TextAlign.right,
                icon: Icon(Icons.format_align_right),
                tooltip: '右对齐',
              ),
            ],
            selected: {settings.lyricAlignment},
            onSelectionChanged: (selection) {
              if (selection.isNotEmpty) {
                settings.setLyricAlignment(selection.first);
              }
            },
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('歌词弹性滚动'),
          value: settings.enableLyricElasticScroll,
          onChanged: settings.setEnableLyricElasticScroll,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.format_bold_rounded),
          title: Text('歌词字体粗细：w${(settings.lyricFontWeightIndex + 1) * 100}'),
          subtitle: Slider(
            value: settings.lyricFontWeightIndex.toDouble(),
            min: 0,
            max: 8,
            divisions: 8,
            label: 'w${(settings.lyricFontWeightIndex + 1) * 100}',
            onChanged: (value) =>
                settings.setLyricFontWeightIndex(value.round()),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('歌词行模糊'),
          value: settings.enableLyricBlur,
          onChanged: settings.setEnableLyricBlur,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('高亮歌词'),
          value: settings.highlightActiveLyric,
          onChanged: settings.setHighlightActiveLyric,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Row(
            children: [
              Text('歌词外发光'),
              SizedBox(width: 4),
              InfoIcon('为播放页歌词添加柔和外发光。发光颜色与透明度会跟随每行歌词，默认关闭。'),
            ],
          ),
          subtitle: const Text('开启后可能会造成卡顿'),
          value: settings.playbackLyricGlowEnabled,
          onChanged: settings.setPlaybackLyricGlowEnabled,
        ),
        if (settings.playbackLyricGlowEnabled)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              '发光范围：${settings.playbackLyricGlowRadius.toStringAsFixed(0)}',
            ),
            subtitle: Slider(
              value: settings.playbackLyricGlowRadius,
              min: 2,
              max: 20,
              divisions: 18,
              label: settings.playbackLyricGlowRadius.toStringAsFixed(0),
              onChanged: settings.setPlaybackLyricGlowRadius,
            ),
          ),
      ],
    );
  }

  Widget _lyricSourcePage(BuildContext context, SettingsProvider settings) {
    return ListView(
      key: const ValueKey('lyric-settings-source-page'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('从网络获取歌词'),
          value: settings.enableOnlineLyrics,
          onChanged: settings.setEnableOnlineLyrics,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('翻译'),
          value: settings.enableLyricTranslation,
          onChanged: (value) async {
            await settings.setEnableLyricTranslation(value);
            if (!context.mounted || !settings.enableOnlineLyrics) return;
            await context.read<PlaylistContentNotifier>().reloadCurrentLyrics();
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('歌词源自动回退'),
          value: settings.enableLyricSourceFallback,
          onChanged: (value) async {
            await settings.setEnableLyricSourceFallback(value);
            if (!context.mounted || !settings.enableOnlineLyrics) return;
            await context.read<PlaylistContentNotifier>().reloadCurrentLyrics();
          },
        ),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          expandedInsets: EdgeInsets.zero,
          style: widget.transparentBackground
              ? ButtonStyle(
                  backgroundColor: WidgetStateProperty.all(Colors.transparent),
                  side: WidgetStateProperty.all(
                    BorderSide(color: Theme.of(context).colorScheme.outline),
                  ),
                )
              : null,
          segments: const [
            ButtonSegment(value: 'netease', label: Text('网抑')),
            ButtonSegment(value: 'qq', label: Text('企鹅')),
            ButtonSegment(value: 'kugou', label: Text('库狗')),
          ],
          selected: {settings.primaryLyricSource},
          onSelectionChanged: (selection) {
            if (selection.isEmpty) return;
            final primary = selection.first;
            settings.setPrimaryLyricSource(primary);
            settings.setSecondaryLyricSource(
              networkLyricSourceOrder(primary)[1],
            );
          },
        ),
      ],
    );
  }
}

class _AudioEffectsSheet extends StatefulWidget {
  const _AudioEffectsSheet({required this.transparentBackground});

  final bool transparentBackground;

  @override
  State<_AudioEffectsSheet> createState() => _AudioEffectsSheetState();
}

class _AudioEffectsSheetState extends State<_AudioEffectsSheet> {
  int _section = 0;
  final Map<int, double> _draggingEqualizerGains = {};

  static const _sections = [
    (icon: Icons.tune, label: '自定义均衡器'),
    (icon: Icons.graphic_eq, label: '音频效果'),
  ];

  static const _effects = <int, List<({String id, String label})>>{
    1: [
      (id: 'crossfeed', label: '交叉混音'),
      (id: 'earwax', label: 'Bauer 空间模拟'),
      (id: 'widerStereo', label: '立体声扩展'),
      (id: 'haas', label: 'Haas 空间效果'),
      (id: 'vocalBoost', label: '人声增强'),
      (id: 'vocalRemover', label: '人声削弱'),
    ],
    2: [
      (id: 'acompressor', label: '动态范围压缩'),
      (id: 'softClip', label: '柔和削波'),
      (id: 'deNoise', label: '背景降噪'),
    ],
    3: [
      (id: 'virtualbass', label: '低音增强'),
      (id: 'subboost', label: '极重低音'),
      (id: 'crystalizer', label: '高频增强'),
      (id: 'tilt', label: '倾斜均衡'),
    ],
    4: [
      (id: 'vinyl', label: '黑胶/收音机'),
      (id: 'exciter', label: '谐波激励'),
      (id: 'echo', label: '回声与空间延迟'),
    ],
    5: [
      (id: 'deesser', label: '人声齿音消除'),
      (id: 'declip', label: '数字破音修复'),
      (id: 'arnndn', label: '人声降噪'),
    ],
  };

  @override
  Widget build(BuildContext context) {
    context.select<PlaylistContentNotifier, int>(
      (notifier) => Object.hash(
        notifier.currentPitch,
        notifier.currentPlaybackRate,
        notifier.equalizerPresetName,
        Object.hashAll(notifier.equalizerGains),
        Object.hashAll(notifier.enabledEffects.toList()..sort()),
        notifier.arnndnModelPath,
      ),
    );
    final notifier = context.read<PlaylistContentNotifier>();
    final scheme = Theme.of(context).colorScheme;
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 68,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: widget.transparentBackground
                ? Colors.transparent
                : scheme.surfaceContainer,
            border: Border(right: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Column(
            children: [
              for (var index = 0; index < _sections.length; index++) ...[
                Tooltip(
                  message: _sections[index].label,
                  child: IconButton.filledTonal(
                    isSelected: _section == index,
                    style: widget.transparentBackground
                        ? IconButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            side: BorderSide(color: scheme.outlineVariant),
                          )
                        : null,
                    selectedIcon: Icon(_sections[index].icon),
                    icon: Icon(_sections[index].icon),
                    onPressed: () => setState(() => _section = index),
                  ),
                ),
                const SizedBox(height: 6),
              ],
            ],
          ),
        ),
        Expanded(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 10, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _sections[_section].label,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        setState(_draggingEqualizerGains.clear);
                        notifier.resetAudioControls();
                      },
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('重置'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _section == 0
                    ? _equalizer(context, notifier)
                    : _effectList(context, notifier),
              ),
            ],
          ),
        ),
      ],
    );
    return Material(
      color: widget.transparentBackground ? Colors.transparent : scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }

  Widget _equalizer(BuildContext context, PlaylistContentNotifier notifier) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Text('当前预设：${notifier.equalizerPresetName}'),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: PlaylistContentNotifier.equalizerPresets
                .skip(1)
                .map(
                  (preset) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: TransparentChipSurface(
                      enabled: widget.transparentBackground,
                      child: ChoiceChip(
                        label: Text(preset.name),
                        selected: preset.name == notifier.equalizerPresetName,
                        backgroundColor: widget.transparentBackground
                            ? Colors.transparent
                            : null,
                        selectedColor: widget.transparentBackground
                            ? Colors.transparent
                            : null,
                        side: widget.transparentBackground
                            ? BorderSide(
                                color: Theme.of(context).colorScheme.outline,
                              )
                            : null,
                        onSelected: (_) {
                          setState(_draggingEqualizerGains.clear);
                          notifier.applyEqualizerPreset(preset);
                        },
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 8),
        ...List.generate(PlaylistContentNotifier.equalizerFrequencies.length, (
          index,
        ) {
          final frequency = PlaylistContentNotifier.equalizerFrequencies[index];
          final gain =
              _draggingEqualizerGains[index] ?? notifier.equalizerGains[index];
          return Row(
            children: [
              SizedBox(width: 64, child: Text(_frequency(frequency))),
              Expanded(
                child: Slider(
                  min: -12,
                  max: 12,
                  divisions: 48,
                  value: gain,
                  onChangeStart: (value) {
                    setState(() => _draggingEqualizerGains[index] = value);
                  },
                  onChanged: (value) {
                    setState(() => _draggingEqualizerGains[index] = value);
                    notifier.previewEqualizerBand(index, value);
                  },
                  onChangeEnd: (value) async {
                    await notifier.commitEqualizerBand(index, value);
                    if (!mounted) return;
                    setState(() => _draggingEqualizerGains.remove(index));
                  },
                ),
              ),
              SizedBox(width: 55, child: Text('${gain.toStringAsFixed(1)} dB')),
            ],
          );
        }),
      ],
    );
  }

  Widget _effectList(BuildContext context, PlaylistContentNotifier notifier) {
    final effects = _effects.values.expand((group) => group).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Text(
          '音效可组合使用；存在冲突的效果会自动互斥。',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: effects.map((effect) {
            final selected = notifier.isEffectEnabled(effect.id);
            return TransparentChipSurface(
              enabled: widget.transparentBackground,
              child: FilterChip(
                selected: selected,
                showCheckmark: true,
                backgroundColor: widget.transparentBackground
                    ? Colors.transparent
                    : null,
                selectedColor: widget.transparentBackground
                    ? Colors.transparent
                    : null,
                side: widget.transparentBackground
                    ? BorderSide(color: Theme.of(context).colorScheme.outline)
                    : null,
                avatar: Icon(_effectIcon(effect.id), size: 18),
                label: Text(effect.label),
                onSelected: (enabled) async {
                  if (effect.id == 'arnndn' &&
                      enabled &&
                      notifier.arnndnModelPath == null) {
                    final path = await _pickNoiseModel();
                    if (path == null) return;
                    await notifier.setArnndnModelPath(path);
                  }
                  await notifier.toggleEffect(effect.id, enabled);
                },
              ),
            );
          }).toList(),
        ),
        if (_section == 1) ...[
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () async {
              final path = await _pickNoiseModel();
              if (path == null) return;
              await notifier.setArnndnModelPath(path);
              if (context.mounted) {
                context.read<NotificationService>().success('人声降噪模型已保存');
              }
            },
            icon: const Icon(Icons.folder_open),
            label: Text(
              notifier.arnndnModelPath == null ? '选择 .rnnn 模型' : '更换降噪模型',
            ),
          ),
        ],
      ],
    );
  }

  Future<String?> _pickNoiseModel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['rnnn'],
      );
      final source = result?.files.single.path;
      if (source == null) return null;
      final directory = await getApplicationSupportDirectory();
      final modelDirectory = Directory(p.join(directory.path, 'models'));
      await modelDirectory.create(recursive: true);
      final destination = p.join(modelDirectory.path, p.basename(source));
      await File(source).copy(destination);
      return destination;
    } catch (error) {
      if (mounted) {
        context.read<NotificationService>().error('无法保存降噪模型：$error');
      }
      return null;
    }
  }

  IconData _effectIcon(String id) => switch (id) {
    'crossfeed' || 'earwax' || 'widerStereo' || 'haas' => Icons.surround_sound,
    'vocalBoost' ||
    'vocalRemover' ||
    'deesser' ||
    'arnndn' => Icons.record_voice_over,
    'acompressor' || 'softClip' => Icons.compress,
    'deNoise' => Icons.noise_control_off,
    'virtualbass' || 'subboost' => Icons.speaker,
    'crystalizer' || 'tilt' => Icons.equalizer,
    'vinyl' => Icons.album,
    'exciter' => Icons.bolt,
    'echo' => Icons.multitrack_audio,
    'declip' => Icons.healing,
    _ => Icons.tune,
  };
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({
    required this.onSectionChanged,
    required this.onSwipeBack,
  });

  final ValueChanged<String> onSectionChanged;
  final VoidCallback onSwipeBack;

  @override
  Widget build(BuildContext context) {
    return SettingPage(
      onSectionChanged: onSectionChanged,
      onSwipeBackFromFirstSection: onSwipeBack,
    );
  }
}

class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({super.key, required this.child});

  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin<_KeepAlivePage> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.selectable = false,
  });

  final String label;
  final String value;
  final bool selectable;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 104,
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
        Expanded(child: selectable ? SelectableText(value) : Text(value)),
      ],
    ),
  );
}

class _RequestedGroupArtwork extends StatefulWidget {
  const _RequestedGroupArtwork({
    required this.song,
    required this.overrideArtwork,
    required this.fallbackIcon,
    required this.highResolution,
    required this.displaySize,
  });

  final Song? song;
  final Uint8List? overrideArtwork;
  final IconData fallbackIcon;
  final bool highResolution;
  final ArtworkSize displaySize;

  @override
  State<_RequestedGroupArtwork> createState() => _RequestedGroupArtworkState();
}

class _RequestedGroupArtworkState extends State<_RequestedGroupArtwork> {
  PlaylistContentNotifier? _notifier;
  String? _requestedPath;
  bool _requestedFullResolution = false;
  Listenable? _coverListenable;
  bool _recoveryScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _notifier ??= context.read<PlaylistContentNotifier>();
    _syncCoverRequest();
  }

  @override
  void didUpdateWidget(covariant _RequestedGroupArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    final overrideChanged =
        (oldWidget.overrideArtwork?.isNotEmpty ?? false) !=
        (widget.overrideArtwork?.isNotEmpty ?? false);
    if (oldWidget.song?.filePath != widget.song?.filePath || overrideChanged) {
      _syncCoverRequest();
      return;
    }
    if (oldWidget.highResolution != widget.highResolution) {
      _releaseCover();
      _requestCover(widget.song?.filePath);
    }
  }

  void _syncCoverRequest() {
    if (widget.overrideArtwork?.isNotEmpty == true) {
      _releaseCover();
      return;
    }
    final filePath = widget.song?.filePath;
    if (filePath == _requestedPath) return;
    _releaseCover();
    _requestCover(filePath);
  }

  void _requestCover(String? filePath) {
    if (filePath == null || filePath == _requestedPath) return;
    final notifier = _notifier;
    if (notifier == null) return;
    _requestedPath = filePath;
    _requestedFullResolution = widget.highResolution;
    _coverListenable = notifier.coverListenableForSongPath(filePath)
      ..addListener(_handleCoverChanged);
    notifier.requestSongCover(
      filePath,
      fullResolution: _requestedFullResolution,
    );
  }

  void _releaseCover() {
    final path = _requestedPath;
    if (path == null) return;
    _coverListenable?.removeListener(_handleCoverChanged);
    _coverListenable = null;
    _notifier?.releaseSongCover(path, fullResolution: _requestedFullResolution);
    _requestedPath = null;
    _requestedFullResolution = false;
  }

  void _handleCoverChanged() {
    _recoveryScheduled = false;
    if (mounted) setState(() {});
  }

  void _scheduleRecovery() {
    if (_recoveryScheduled || _requestedPath == null) return;
    _recoveryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _recoveryScheduled = false;
      final path = _requestedPath;
      if (path != null) {
        _notifier?.recoverSongCover(
          path,
          fullResolution: _requestedFullResolution,
        );
      }
    });
  }

  @override
  void dispose() {
    _releaseCover();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final override = widget.overrideArtwork;
    final song = widget.song;
    final artwork = override != null && override.isNotEmpty
        ? override
        : song == null
        ? null
        : widget.highResolution
        ? _notifier?.displayCoverForSong(song)
        : _notifier?.displayThumbnailForSong(song);
    if (artwork == null || artwork.isEmpty) {
      _scheduleRecovery();
      final scheme = Theme.of(context).colorScheme;
      return ColoredBox(
        color: scheme.surfaceContainerHigh,
        child: Center(
          child: Icon(
            widget.fallbackIcon,
            size: 42,
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }
    if (widget.highResolution) {
      return LayoutBuilder(
        builder: (context, constraints) => ArtworkImage(
          bytes: artwork,
          size: widget.displaySize,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          progressive: true,
          filterQuality: FilterQuality.high,
        ),
      );
    }
    return ArtworkImage(
      bytes: artwork,
      size: ArtworkSize.thumbnail,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
    );
  }
}

class _AtomicNowPlayingCover extends StatelessWidget {
  const _AtomicNowPlayingCover({required this.songPath, required this.size});

  final String songPath;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _preparedPlaybackArtworkSignal,
      builder: (context, _) {
        final currentPrepared = _preparedPlaybackArtwork;
        final previousPrepared = _previousPreparedPlaybackArtwork;
        final exactPrepared = currentPrepared?.path == songPath
            ? currentPrepared
            : previousPrepared?.path == songPath
            ? previousPrepared
            : null;
        final retainedPrepared = currentPrepared ?? previousPrepared;
        final prepared =
            exactPrepared ??
            (shouldRetainPreviousNowPlayingArtwork(
                  songPath: songPath,
                  preparedPath: retainedPrepared?.path,
                  handoffTargetPath: _playbackArtworkHandoffTargetPath,
                )
                ? retainedPrepared
                : null);
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox.square(
            dimension: size,
            child: prepared == null
                ? ColoredBox(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    child: Icon(Icons.music_note, size: size * .5),
                  )
                : Image(
                    image: CoverMemoryImage(
                      prepared.bytes,
                      targetPixels: prepared.targetPixels,
                    ),
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stackTrace) => ColoredBox(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      child: Icon(Icons.music_note, size: size * .5),
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class _Cover extends StatefulWidget {
  const _Cover({required this.song, this.size = 48});
  final Song song;
  final double size;

  @override
  State<_Cover> createState() => _CoverState();
}

class _CoverState extends State<_Cover> {
  PlaylistContentNotifier? _notifier;
  String? _requestedPath;
  bool _requestedFullResolution = false;
  Listenable? _coverListenable;
  bool _recoveryScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _notifier ??= context.read<PlaylistContentNotifier>();
    _requestCover(widget.song.filePath, fullResolution: false);
  }

  @override
  void didUpdateWidget(covariant _Cover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.filePath != widget.song.filePath) {
      _releaseCover();
      _requestCover(widget.song.filePath, fullResolution: false);
    }
  }

  Uint8List? _artFor(Song song, {required bool fullResolution}) =>
      fullResolution
      ? _notifier?.displayFullCoverForSong(song)
      : _notifier?.displayThumbnailForSong(song);

  void _requestCover(String filePath, {required bool fullResolution}) {
    if (_requestedPath == filePath &&
        _requestedFullResolution == fullResolution) {
      return;
    }
    _requestedPath = filePath;
    _requestedFullResolution = fullResolution;
    final notifier = _notifier;
    if (notifier == null) return;
    _coverListenable = notifier.coverListenableForSongPath(filePath)
      ..addListener(_handleCoverChanged);
    notifier.requestSongCover(filePath, fullResolution: fullResolution);
  }

  void _releaseCover() {
    final path = _requestedPath;
    if (path != null) {
      _coverListenable?.removeListener(_handleCoverChanged);
      _coverListenable = null;
      _notifier?.releaseSongCover(
        path,
        fullResolution: _requestedFullResolution,
      );
      _requestedPath = null;
      _requestedFullResolution = false;
    }
  }

  void _handleCoverChanged() {
    _recoveryScheduled = false;
    if (mounted) setState(() {});
  }

  void _scheduleRecovery() {
    if (_recoveryScheduled || _requestedPath == null) return;
    _recoveryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _recoveryScheduled = false;
      final path = _requestedPath;
      if (path != null) {
        _notifier?.recoverSongCover(
          path,
          fullResolution: _requestedFullResolution,
        );
      }
    });
  }

  @override
  void dispose() {
    _releaseCover();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final art = _artFor(widget.song, fullResolution: false);
    final thumbnailUnavailable =
        _notifier?.artworkResolutionStateForPath(widget.song.filePath) ==
        ArtworkResolutionState.unavailable;
    if ((art == null || art.isEmpty) && !thumbnailUnavailable) {
      _scheduleRecovery();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: art == null
            ? ColoredBox(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Icon(Icons.music_note, size: widget.size * .5),
              )
            : ArtworkImage(
                bytes: art,
                size: ArtworkSize.thumbnail,
                logicalSize: widget.size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                progressive: false,
                filterQuality: FilterQuality.medium,
                errorBuilder: (context, error, stackTrace) => ColoredBox(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: Icon(Icons.music_note, size: widget.size * .5),
                ),
              ),
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({
    required this.name,
    required this.onTap,
    this.subtitle,
    this.selected = false,
    this.icon = Icons.queue_music,
    this.onLongPress,
  });
  final String name;
  final String? subtitle;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Material(
        color: selected
            ? Theme.of(context).colorScheme.secondaryContainer
            : Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 120,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon),
                  const Spacer(),
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _SongSearchScope { library, currentPlaylist, collection }

class _SongSearchDelegate extends SearchDelegate<void> {
  _SongSearchDelegate({
    required String initialQuery,
    required this.onChanged,
    required this.scope,
    required this.sourceSongs,
    this.onPlay,
  }) : super(
         searchFieldLabel: scope == _SongSearchScope.currentPlaylist
             ? '在当前歌单中搜索'
             : scope == _SongSearchScope.collection
             ? '在当前歌手/专辑中搜索'
             : '搜索音乐库',
       ) {
    query = initialQuery;
  }

  final ValueChanged<String> onChanged;
  final _SongSearchScope scope;
  final List<Song> sourceSongs;
  final Future<void> Function(List<Song> songs, int index)? onPlay;

  @override
  List<Widget> buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
          onChanged(query);
        },
      ),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () {
      onChanged(query);
      close(context, null);
    },
  );

  @override
  Widget buildResults(BuildContext context) => _results(context);

  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  Widget _results(BuildContext context) {
    final songs = context.read<PlaylistContentNotifier>().searchSongs(
      query,
      sourceSongs,
    );
    return _SongList(
      songs: songs,
      onPlay: (index) async {
        final notifier = context.read<PlaylistContentNotifier>();
        final song = songs[index];
        if (onPlay != null) {
          await onPlay!(songs, index);
        } else if (scope == _SongSearchScope.currentPlaylist) {
          await notifier.playCurrentPlaylistSearchResult(song);
        } else {
          await notifier.playAllSongsSearchResult(song);
        }
        if (context.mounted) {
          close(context, null);
        }
      },
    );
  }
}

class _GroupSearchDelegate extends SearchDelegate<void> {
  _GroupSearchDelegate({required this.kind, required this.groups})
    : super(searchFieldLabel: '搜索$kind');

  final String kind;
  final Map<String, List<Song>> groups;

  @override
  List<Widget> buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );

  @override
  Widget buildResults(BuildContext context) => _results(context);

  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  Widget _results(BuildContext context) {
    final normalizedQuery = query.trim().toLowerCase();
    final entries =
        groups.entries
            .where(
              (entry) =>
                  normalizedQuery.isEmpty ||
                  entry.key.toLowerCase().contains(normalizedQuery),
            )
            .toList(growable: false)
          ..sort((first, second) => first.key.compareTo(second.key));
    if (entries.isEmpty) return Center(child: Text('没有匹配的$kind'));
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return ListTile(
          leading: Icon(kind == '歌手' ? Icons.person : Icons.album),
          title: Text(entry.key),
          subtitle: Text('${entry.value.length} 首歌曲'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            final notifier = context.read<PlaylistContentNotifier>();
            Navigator.of(context).push(
              CupertinoPageRoute<void>(
                builder: (_) => _SongCollectionPage(
                  title: entry.key,
                  songs: entry.value,
                  pinScope: kind == '歌手'
                      ? notifier.artistSongsPinScope(entry.key)
                      : notifier.albumSongsPinScope(entry.key),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.audio_file_outlined, size: 56),
          SizedBox(height: 16),
          Text('还没有音乐'),
          Text('进入“歌单”，新建或选择歌单后添加本地音频文件。', textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

String _duration(Duration value) =>
    '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

String _longDuration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  if (hours == 0) return '$minutes 分钟';
  return '$hours 小时 $minutes 分钟';
}

String _frequency(num value) => value >= 1000
    ? '${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)}k Hz'
    : '${value.toStringAsFixed(0)} Hz';

String _dateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}

String _modeLabel(PlayMode mode) => switch (mode) {
  PlayMode.shuffle => '随机播放',
  PlayMode.repeatOne => '单曲循环',
  _ => '列表循环',
};

IconData _modeIcon(PlayMode mode) => switch (mode) {
  PlayMode.shuffle => Icons.shuffle,
  PlayMode.repeatOne => Icons.repeat_one,
  _ => Icons.repeat,
};
