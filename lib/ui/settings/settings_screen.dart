import 'package:flutter/material.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../data/settings_store.dart';
import '../../data/storage_repository.dart';
import '../app_scope.dart';
import '../channels/channels_screen.dart';
import '../debug/media_debug_screen.dart';
import '../debug/td_debug_screen.dart';
import '../motion.dart';
import '../theme.dart';
import '../widgets/pull_to_dismiss.dart';
import '../widgets/tappable.dart';

/// Your account, and everything configurable in one place.
///
/// Before this the settings that existed were four icons in the feed header and
/// nothing was written to disk, so every choice reset on launch.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  td.User? _me;
  StorageUsage? _usage;
  var _started = false;
  var _clearing = false;
  var _backfilling = false;
  String? _notice;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _loadAccount();
    _loadStorage();
  }

  Future<void> _loadAccount() async {
    try {
      final me = await AppScope.clientOf(context).send<td.User>(const td.GetMe());
      if (mounted) setState(() => _me = me);
    } catch (_) {
      // The screen is still useful without the name on it, so a failure here
      // leaves the header as a placeholder rather than an error page.
    }
  }

  Future<void> _loadStorage() async {
    try {
      final usage = await AppScope.storageOf(context).usage();
      if (mounted) setState(() => _usage = usage);
    } catch (_) {
      // Same: the rest of the screen does not depend on it.
    }
  }

  Future<void> _clearCache() async {
    setState(() => _clearing = true);
    try {
      final freed = await AppScope.storageOf(context).clearMedia();
      await _loadStorage();
      if (mounted) {
        setState(() => _notice = freed > 0
            ? 'Freed ${formatBytes(freed)}.'
            : 'Nothing to clear.');
      }
    } catch (e) {
      if (mounted) setState(() => _notice = 'Could not clear: $e');
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _backfill() async {
    setState(() {
      _backfilling = true;
      _notice = 'Starting…';
    });
    try {
      final total = await AppScope.messagesOf(context).backfillAll(
        perChannel: 40,
        onProgress: (done, all) {
          if (mounted) setState(() => _notice = 'Channel $done of $all');
        },
      );
      if (mounted) setState(() => _notice = 'Pulled $total posts.');
    } catch (e) {
      if (mounted) setState(() => _notice = 'Backfill failed: $e');
    } finally {
      if (mounted) setState(() => _backfilling = false);
    }
  }

  /// Confirmed, and the wording says what it costs.
  ///
  /// This is the one irreversible action in the app: it ends the session on
  /// Telegram's side, so the next launch needs a new code, and repeated logins
  /// are what trip the flood limits.
  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'This ends the session on Telegram, so signing back in needs a new '
          'login code sent to your phone. Cached posts are deleted with it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await AppScope.authOf(context).signOut();
    // No navigation here: logOut makes TDLib walk its own state machine back to
    // the login screen, and AuthGate is already listening for that.
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.settingsOf(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          PullToDismiss(child: _AccountHeader(me: _me)),
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: AnimatedSizeSwitcher(
                child: Text(
                  _notice!,
                  key: ValueKey(_notice),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),

          _Section(
            title: 'Appearance',
            children: [_ThemePicker(settings: settings)],
          ),

          _Section(
            title: 'Data',
            children: [
              SwitchListTile(
                title: const Text('Data saver'),
                subtitle: const Text(
                  'Stops images and video loading on their own',
                ),
                value: settings.dataSaver,
                onChanged: settings.setDataSaver,
              ),
              // Shown as off and disabled under data saver rather than silently
              // rewritten, so turning data saver back off restores what you had
              // chosen instead of a guess.
              SwitchListTile(
                title: const Text('Auto-load images'),
                subtitle: Text(
                  settings.dataSaver
                      ? 'Off while data saver is on'
                      : 'Tap a placeholder to load it when off',
                ),
                value: settings.autoLoadImages,
                onChanged:
                    settings.dataSaver ? null : settings.setAutoLoadImages,
              ),
              SwitchListTile(
                title: const Text('Autoplay video'),
                subtitle: Text(
                  settings.dataSaver
                      ? 'Off while data saver is on'
                      : 'Plays muted as it scrolls into view',
                ),
                value: settings.autoplayVideo,
                onChanged:
                    settings.dataSaver ? null : settings.setAutoplayVideo,
              ),
            ],
          ),

          _Section(
            title: 'Storage',
            children: [
              _StorageRows(usage: _usage),
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined),
                title: const Text('Clear cached media'),
                subtitle: const Text('Keeps your posts and your session'),
                trailing: _clearing
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onTap: _clearing ? null : _clearCache,
              ),
            ],
          ),

          _Section(
            title: 'Content',
            children: [
              ListTile(
                leading: const Icon(Icons.rss_feed),
                title: const Text('Channels'),
                subtitle: const Text('Which channels feed For You and Following'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ChannelsScreen()),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Pull recent posts'),
                subtitle: const Text('Fetches history for every tracked channel'),
                trailing: _backfilling
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onTap: _backfilling ? null : _backfill,
              ),
            ],
          ),

          _Section(
            title: 'Account',
            children: [
              ListTile(
                leading: Icon(
                  Icons.logout,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Sign out',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                subtitle: const Text('Needs a new login code to come back'),
                onTap: _signOut,
              ),
            ],
          ),

          // Understated on purpose: reachable, not advertised.
          const SizedBox(height: 8),
          _QuietRow(
            label: 'Raw TDLib updates',
            page: TdDebugScreen(),
          ),
          const _QuietRow(
            label: 'Media cache inspector',
            page: MediaDebugScreen(),
          ),
        ],
      ),
    );
  }
}

/// Avatar, name and handle.
class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.me});

  final td.User? me;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = this.me;
    final name = me == null
        ? 'Loading…'
        : [me.firstName, me.lastName].where((p) => p.isNotEmpty).join(' ');
    final username = me?.usernames?.activeUsernames.firstOrNull;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              _initials(name),
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'You' : name,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  // No "@", matching the feed. The phone number is deliberately
                  // not shown: it is the one piece of account data on this screen
                  // that would be sensitive in a screenshot.
                  [?username, if (me != null) 'signed in'].join(' · '),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemePicker extends StatelessWidget {
  const _ThemePicker({required this.settings});

  final SettingsStore settings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: SegmentedButton<ThemeMode>(
        segments: const [
          ButtonSegment(
            value: ThemeMode.system,
            icon: Icon(Icons.brightness_auto_outlined),
            label: Text('System'),
          ),
          ButtonSegment(
            value: ThemeMode.light,
            icon: Icon(Icons.light_mode_outlined),
            label: Text('Light'),
          ),
          ButtonSegment(
            value: ThemeMode.dark,
            icon: Icon(Icons.dark_mode_outlined),
            label: Text('Dark'),
          ),
        ],
        selected: {settings.themeMode},
        onSelectionChanged: (selection) =>
            settings.setThemeMode(selection.first),
        showSelectedIcon: false,
      ),
    );
  }
}

class _StorageRows extends StatelessWidget {
  const _StorageRows({required this.usage});

  final StorageUsage? usage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usage = this.usage;

    if (usage == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Text('Measuring…'),
      );
    }

    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: theme.textTheme.bodyMedium),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        children: [
          row('Cached media', formatBytes(usage.mediaBytes)),
          row('Files', '${usage.fileCount}'),
          row('Session database', formatBytes(usage.databaseBytes)),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      child: Container(
        decoration: BoxDecoration(
          color: containerColor(context),
          borderRadius: BorderRadius.circular(Shapes.card),
        ),
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
              child: Text(
                title,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _QuietRow extends StatelessWidget {
  const _QuietRow({required this.label, required this.page});

  final String label;
  final Widget page;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tappable(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => page),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
        child: Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

String _initials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.isEmpty) return '?';
  return words.take(2).map((w) => w.characters.first).join().toUpperCase();
}
