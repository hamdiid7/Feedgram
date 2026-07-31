import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../data/channel_repository.dart';
import '../data/media_cache.dart';
import '../data/media_repository.dart';
import '../data/message_repository.dart';
import '../telegram/auth/auth_controller.dart';
import '../telegram/td_paths.dart';
import '../telegram/telegram_client.dart';
import 'feed/playback_coordinator.dart';

/// Owns the single [TelegramClient] and [AuthController] for the process and
/// hands them to descendants.
///
/// One client per process is a hard requirement, not a convenience: TDLib is
/// addressed by a client ID created once, and a second one would mean a second
/// database handle on the same directory.
class AppScope extends StatefulWidget {
  const AppScope({super.key, required this.playback, required this.builder});

  /// Owned above this widget so the navigator observer in `main.dart` can also
  /// reach it.
  final PlaybackCoordinator playback;

  final Widget Function(BuildContext context) builder;

  static AppScopeData of(BuildContext context) => _of(context);

  static AppScopeData _of(BuildContext context) {
    final data = context.dependOnInheritedWidgetOfExactType<AppScopeData>();
    assert(data != null, 'No AppScope above this widget');
    return data!;
  }

  static TelegramClient clientOf(BuildContext context) =>
      _of(context).client;

  static AuthController authOf(BuildContext context) => _of(context).auth;

  static AppDatabase databaseOf(BuildContext context) => _of(context).database;

  static ChannelRepository channelsOf(BuildContext context) =>
      _of(context).channels;

  static MessageRepository messagesOf(BuildContext context) =>
      _of(context).messages;

  static MediaRepository mediaOf(BuildContext context) => _of(context).media;

  static MediaCache mediaCacheOf(BuildContext context) =>
      _of(context).mediaCache;

  static PlaybackCoordinator playbackOf(BuildContext context) =>
      _of(context).playback;

  /// Whether feed photos upgrade themselves to full resolution while scrolling.
  ///
  /// Off means placeholder-until-tapped, which is the cheap mode the spec's
  /// bandwidth note describes.
  static bool autoLoadImagesOf(BuildContext context) =>
      _of(context).autoLoadImages;

  static void setAutoLoadImages(BuildContext context, bool value) =>
      _of(context).setAutoLoadImages(value);

  @override
  State<AppScope> createState() => _AppScopeState();
}

class _AppScopeState extends State<AppScope>
    with WidgetsBindingObserver {
  final _client = TelegramClient();

  PlaybackCoordinator get _playback => widget.playback;

  AuthController? _auth;
  AppDatabase? _database;
  ChannelRepository? _channels;
  MessageRepository? _messages;
  MediaRepository? _media;
  MediaCache? _mediaCache;

  /// Session-only: not persisted, so a restart returns to auto-loading.
  var _autoLoadImages = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  /// Backgrounding must stop playback outright: an Android app that keeps a
  /// decoder and audio session alive off-screen is both a battery problem and a
  /// way to leak sound over whatever the user switched to.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _playback.appForeground = state == AppLifecycleState.resumed;
  }

  Future<void> _bootstrap() async {
    try {
      // Both of these are async platform work, so they have to finish before the
      // controller can send setTdlibParameters or a repository can query.
      final paths = await TdPaths.resolve();
      final database = await AppDatabase.open();

      final auth = AuthController(client: _client, paths: paths);
      final channels = ChannelRepository(client: _client, db: database);
      final messages = MessageRepository(client: _client, db: database);
      final media = MediaRepository(client: _client);
      final mediaCache = MediaCache(repository: media);

      // Drift connects lazily, so touch the database now. SQLite reaches the app
      // through Dart build hooks — a completely different mechanism from TDLib's
      // bundled .so — and a missing libsqlite3 should surface here rather than
      // halfway down the first feed query.
      await channels.countChannels();

      if (!mounted) return;
      setState(() {
        _database = database;
        _channels = channels;
        _messages = messages;
        _media = media;
        _mediaCache = mediaCache;
        _auth = auth;
      });
      await auth.start();

      // Live updates must be running before the feed is shown, so a post that
      // arrives while the user is looking at the list lands in the database.
      messages.startLiveUpdates();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  void _setAutoLoadImages(bool value) {
    if (_autoLoadImages == value) return;
    setState(() => _autoLoadImages = value);
    // Cheap mode covers video too, or the toggle would still burn data.
    _playback.autoplayEnabled = value;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Not disposed here — it is owned by the app above this widget.
    _mediaCache?.dispose();
    _auth?.dispose();
    _client.dispose();
    _database?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _Splash(message: 'Startup failed:\n$_error');
    }
    final auth = _auth;
    final database = _database;
    final channels = _channels;
    final messages = _messages;
    final media = _media;
    final mediaCache = _mediaCache;
    if (auth == null ||
        database == null ||
        channels == null ||
        messages == null ||
        media == null ||
        mediaCache == null) {
      return const _Splash();
    }
    return AppScopeData(
      client: _client,
      auth: auth,
      database: database,
      channels: channels,
      messages: messages,
      media: media,
      mediaCache: mediaCache,
      playback: _playback,
      autoLoadImages: _autoLoadImages,
      setAutoLoadImages: _setAutoLoadImages,
      child: Builder(builder: widget.builder),
    );
  }
}

class AppScopeData extends InheritedWidget {
  const AppScopeData({
    super.key,
    required this.client,
    required this.auth,
    required this.database,
    required this.channels,
    required this.messages,
    required this.media,
    required this.mediaCache,
    required this.playback,
    required this.autoLoadImages,
    required this.setAutoLoadImages,
    required super.child,
  });

  final TelegramClient client;
  final AuthController auth;
  final AppDatabase database;
  final ChannelRepository channels;
  final MessageRepository messages;
  final MediaRepository media;
  final MediaCache mediaCache;
  final PlaybackCoordinator playback;
  final bool autoLoadImages;
  final void Function(bool) setAutoLoadImages;

  @override
  bool updateShouldNotify(AppScopeData oldWidget) =>
      client != oldWidget.client ||
      auth != oldWidget.auth ||
      database != oldWidget.database ||
      channels != oldWidget.channels ||
      messages != oldWidget.messages ||
      media != oldWidget.media ||
      mediaCache != oldWidget.mediaCache ||
      playback != oldWidget.playback ||
      autoLoadImages != oldWidget.autoLoadImages;
}

class _Splash extends StatelessWidget {
  const _Splash({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: message == null
              ? const CircularProgressIndicator()
              : Text(message!, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
