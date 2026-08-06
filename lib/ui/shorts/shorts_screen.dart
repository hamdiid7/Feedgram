import 'package:flutter/material.dart';

import '../../data/message_repository.dart';
import '../app_scope.dart';
import '../feed/post_media.dart';
import '../feed/post_text.dart';
import '../feed/post_video.dart';
import '../motion.dart';

/// Shorts: one video per screen, swiped vertically.
///
/// Reads the same cached posts as the feeds, filtered to video and GIF. Nothing
/// new is downloaded to fill it — a browsing surface that pulls fresh clips on
/// every swipe is exactly the runaway data use the rest of the app is careful to
/// avoid, so this shows what is already there.
class ShortsScreen extends StatefulWidget {
  const ShortsScreen({super.key});

  @override
  State<ShortsScreen> createState() => _ShortsScreenState();
}

class _ShortsScreenState extends State<ShortsScreen>
    with AutomaticKeepAliveClientMixin {
  /// Kept alive like the feeds: coming back to a half-watched clip and finding
  /// the list reset to the top is the same complaint as the feed reloading.
  @override
  bool get wantKeepAlive => true;

  final _pages = PageController();

  List<FeedEntry>? _entries;
  Object? _error;
  var _started = false;
  var _index = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final entries = await AppScope.messagesOf(context).videoPosts();
      if (mounted) setState(() => _entries = entries);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final entries = _entries;
    final error = _error;

    if (error != null) return _Message(text: 'Could not load: $error');
    if (entries == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (entries.isEmpty) {
      return const _Message(
        text: 'No videos cached yet.\n\n'
            'Pull posts from Settings, or scroll a feed with video in it.',
      );
    }

    // Black rather than the theme surface, in both themes. A video sitting on a
    // pale background looks like a mistake, and every other short-video surface
    // people use is black.
    return ColoredBox(
      color: Colors.black,
      child: PageView.builder(
        controller: _pages,
        scrollDirection: Axis.vertical,
        itemCount: entries.length,
        onPageChanged: (index) => setState(() => _index = index),
        itemBuilder: (context, index) => _Short(
          entry: entries[index],
          // Only the visible page gets a player. The coordinator caps decoders
          // at two, and handing it a slot for every page in the list would mean
          // most of them silently losing the grant.
          active: index == _index,
        ),
      ),
    );
  }
}

class _Short extends StatelessWidget {
  const _Short({required this.entry, required this.active});

  final FeedEntry entry;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final message = entry.message;
    final media = PostMedia.decode(message.mediaJson);
    final key = '${message.chatId}:${message.messageId}';

    return Stack(
      fit: StackFit.expand,
      children: [
        // Only the current page gets a player. Not for the decoder budget — the
        // coordinator handles that — but because building one starts fetching the
        // video, and a PageView keeps its neighbours alive: three pages would
        // mean three downloads of up to 150 MB for two clips nobody is watching.
        //
        // Neighbours show their thumbnail instead, so a swipe reveals a picture
        // rather than a placeholder.
        if (!active)
          _Thumbnail(media: media)
        else
          Center(
            child: media == null
              ? const Icon(Icons.videocam_off_outlined, color: Colors.white38)
              // The existing player, unchanged: it already owns the decoder
              // budget, the partial-file streaming and the loading spinner.
              : PostVideoView(
                  media: media,
                  // One stable key per clip. Swapping the key when a page became
                  // current registered it with the playback coordinator as a
                  // brand new slot while the old key sat there still claiming to
                  // be visible — so the grants went to pages nobody was looking
                  // at. The coordinator already decides by visibility, and
                  // VisibilityDetector reports this page at 1.0 and its
                  // neighbours at 0, which is exactly the input it wants.
                  postKey: key,
                  fill: true,
                  // The feed's 10 MB ceiling is a scrolling-past guard. Here the
                  // video is the reason you opened the tab.
                  autoplayLimit: PostVideoView.shortsByteLimit,
                ),
          ),
        // Gradient behind the caption, not a solid bar: the text has to stay
        // readable over an unknown frame without covering the picture.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            ignoring: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 40, 16, 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xCC000000)],
                ),
              ),
              child: _Caption(entry: entry),
            ),
          ),
        ),
      ],
    );
  }
}

/// What a not-yet-current page shows: the post's own thumbnail, which the feed
/// already carries inline and costs no request.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.media});

  final PostMedia? media;

  @override
  Widget build(BuildContext context) {
    final bytes = media?.thumbBytes;
    if (bytes == null) {
      return const Center(
        child: Icon(Icons.videocam_off_outlined, color: Colors.white38),
      );
    }
    return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
  }
}

class _Caption extends StatelessWidget {
  const _Caption({required this.entry});

  final FeedEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final channel = entry.channel;
    final message = entry.message;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white24,
              child: Text(
                _initials(channel.title),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: Colors.white),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                channel.title.isEmpty ? 'Untitled' : channel.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _Stat(icon: Icons.visibility_outlined, value: message.viewCount),
            const SizedBox(width: 12),
            _Stat(icon: Icons.favorite_border, value: message.reactionCount),
          ],
        ),
        if (message.body.isNotEmpty) ...[
          const SizedBox(height: 8),
          // Reuses the feed's precomputed spans, so links and formatting survive
          // rather than being flattened to plain text.
          DefaultTextStyle(
            style: theme.textTheme.bodyMedium!.copyWith(color: Colors.white),
            child: PostText(
              cacheKey: 'short:${message.chatId}:${message.messageId}',
              spansJson: message.spansJson,
              fallbackText: message.body,
              maxLines: 3,
            ),
          ),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.value});

  final IconData icon;
  final int value;

  @override
  Widget build(BuildContext context) {
    if (value <= 0) return const SizedBox.shrink();
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.white70),
        const SizedBox(width: 4),
        Text(
          _compact(value),
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ScaleIn(
                child: Icon(
                  Icons.video_library_outlined,
                  size: 44,
                  color: Colors.white38,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _initials(String title) {
  final words = title.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.isEmpty) return '?';
  return words.take(2).map((w) => w.characters.first).join().toUpperCase();
}

String _compact(int value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
  return '$value';
}
