import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../data/channel_repository.dart';
import '../data/chat_repository.dart';
import '../data/for_you_repository.dart';
import '../data/media_cache.dart';
import '../data/media_repository.dart';
import '../data/message_repository.dart';
import '../data/settings_store.dart';
import '../data/storage_repository.dart';
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
  const AppScope({
    super.key,
    required this.playback,
    required this.settings,
    required this.builder,
  });

  /// Owned above this widget so the navigator observer in `main.dart` can also
  /// reach it.
  final PlaybackCoordinator playback;

  /// Owned above this widget, like [playback] — `MaterialApp` needs it for
  /// `themeMode`, and one store shared with the app means a change made here
  /// reaches the theme instead of two copies disagreeing.
  final SettingsStore settings;

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

  static ChatRepository chatsOf(BuildContext context) => _of(context).chats;

  static MediaRepository mediaOf(BuildContext context) => _of(context).media;

  static MediaCache mediaCacheOf(BuildContext context) =>
      _of(context).mediaCache;

  static PlaybackCoordinator playbackOf(BuildContext context) =>
      _of(context).playback;

  static ForYouRepository forYouOf(BuildContext context) =>
      _of(context).forYou;

  /// Whether feed photos upgrade themselves to full resolution while scrolling.
  ///
  /// Off means placeholder-until-tapped, which is the cheap mode the spec's
  /// bandwidth note describes.
  static bool autoLoadImagesOf(BuildContext context) =>
      _of(context).autoLoadImages;

  static void setAutoLoadImages(BuildContext context, bool value) =>
      _of(context).setAutoLoadImages(value);

  static SettingsStore settingsOf(BuildContext context) =>
      _of(context).settings;

  static StorageRepository storageOf(BuildContext context) =>
      _of(context).storage;

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
  ForYouRepository? _forYou;
  StorageRepository? _storage;
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
      final forYou = ForYouRepository(db: database);
      final storage = StorageRepository(client: _client);
      // Interaction counters drive the ranking, so the repository that applies
      // them needs to be able to rescore.
      messages.forYou = forYou;

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
        _forYou = forYou;
        _storage = storage;
        _auth = auth;
      });

      // The saved data preferences have to reach the playback coordinator, or
      // autoplay would ignore a data-saver setting restored from last launch.
      _settings.addListener(_applyDataSettings);
      _applyDataSettings();
      await auth.start();

      // Live updates must be running before the feed is shown, so a post that
      // arrives while the user is looking at the list lands in the database.
      messages.startLiveUpdates();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  /// Pushes the saved data preferences into the playback coordinator and
  /// rebuilds anything reading them through the scope.
  SettingsStore get _settings => widget.settings;

  void _applyDataSettings() {
    _playback.autoplayEnabled = _settings.autoplayVideo;
    if (mounted) setState(() {});
  }

  void _setAutoLoadImages(bool value) => _settings.setAutoLoadImages(value);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Removed but not disposed: owned above this widget.
    _settings.removeListener(_applyDataSettings);
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
    final forYou = _forYou;
    final storage = _storage;
    // Built here rather than in the bootstrap: it holds no database handle and
    // no state, only the client, so there is nothing to set up asynchronously.
    final chats = ChatRepository(client: _client);
    if (auth == null ||
        database == null ||
        channels == null ||
        messages == null ||
        media == null ||
        mediaCache == null ||
        forYou == null ||
        storage == null) {
      return const _Splash();
    }
    return AppScopeData(
      client: _client,
      auth: auth,
      database: database,
      channels: channels,
      messages: messages,
      chats: chats,
      media: media,
      mediaCache: mediaCache,
      forYou: forYou,
      settings: _settings,
      storage: storage,
      playback: _playback,
      autoLoadImages: _settings.autoLoadImages,
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
    required this.chats,
    required this.media,
    required this.mediaCache,
    required this.forYou,
    required this.settings,
    required this.storage,
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
  final ChatRepository chats;
  final MediaRepository media;
  final MediaCache mediaCache;
  final ForYouRepository forYou;
  final SettingsStore settings;
  final StorageRepository storage;
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
      forYou != oldWidget.forYou ||
      settings != oldWidget.settings ||
      storage != oldWidget.storage ||
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
