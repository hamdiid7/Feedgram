import 'package:flutter/material.dart';

import '../../domain/feed_grouping.dart';
import 'media_viewer.dart';
import 'post_media.dart';

/// Carousel for an album — the several posts Telegram published together.
class PostAlbum extends StatefulWidget {
  const PostAlbum({super.key, required this.album});

  final AlbumPost album;

  @override
  State<PostAlbum> createState() => _PostAlbumState();
}

class _PostAlbumState extends State<PostAlbum> {
  final _controller = PageController();
  var _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Album members arrive newest-first from the feed query, but Telegram
    // published them in ascending message order — that is the order the author
    // intended, so reverse for display.
    final entries = widget.album.entries.reversed.toList();
    final media = [
      for (final entry in entries) PostMedia.decode(entry.message.mediaJson),
    ];

    final aspect = media
            .firstWhere((m) => m != null && m.isVisual, orElse: () => null)
            ?.aspectRatio ??
        1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: aspect,
            child: PageView.builder(
              controller: _controller,
              itemCount: entries.length,
              onPageChanged: (page) => setState(() => _page = page),
              itemBuilder: (context, index) {
                final item = media[index];
                if (item == null) {
                  return ColoredBox(
                      color: theme.colorScheme.surfaceContainerHighest);
                }
                return PostMediaView(
                  media: item,
                  onTap: item.fileId == null
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => MediaViewer(media: item),
                            ),
                          ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < entries.length; i++)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == _page
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.35),
                ),
              ),
            const SizedBox(width: 8),
            Text('${_page + 1}/${entries.length}',
                style: theme.textTheme.bodySmall),
          ],
        ),
      ],
    );
  }
}
