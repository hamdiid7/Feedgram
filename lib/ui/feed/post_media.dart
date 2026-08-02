import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/media_cache.dart';
import '../../data/media_repository.dart';
import '../app_scope.dart';
import '../motion.dart';

/// Media descriptor decoded from `messages.media_json`.
/// One available resolution of a photo.
class PhotoVariant {
  const PhotoVariant({
    required this.fileId,
    required this.width,
    this.remoteId,
  });

  final int fileId;
  final int width;

  /// Persistent id; survives restarts where [fileId] does not.
  final String? remoteId;
}

class PostMedia {
  const PostMedia({
    required this.type,
    this.thumbBytes,
    this.width,
    this.height,
    this.fileId,
    this.label,
    this.variants = const [],
    this.remoteId,
    this.byteSize,
    this.posterId,
    this.posterRemoteId,
    this.streamable = false,
  });

  final String type;

  /// Decoded `minithumbnail` — a tiny JPEG TDLib already gave us.
  final Uint8List? thumbBytes;

  final int? width;
  final int? height;

  /// Largest available file. Used as the fallback when [variants] is empty
  /// (rows written before sizes were stored).
  final int? fileId;

  /// Human-readable detail for non-image content (document name, poll question).
  final String? label;

  /// Every resolution TDLib offers, ascending by width.
  final List<PhotoVariant> variants;

  /// Persistent id for [fileId].
  final String? remoteId;

  /// File size in bytes, when known. Gates video autoplay.
  final int? byteSize;

  /// A real JPEG poster frame, shown whenever a video is not playing. Sharper
  /// than the 32px minithumbnail, which is what made a paused video look blurred.
  final int? posterId;
  final String? posterRemoteId;

  /// TDLib says this file can be played from a partial prefix.
  final bool streamable;

  /// Reference for the poster image, if there is one.
  MediaRef? get posterRef => posterId == null
      ? null
      : MediaRef(fileId: posterId!, remoteId: posterRemoteId);

  /// The smallest variant that still covers [targetWidth] logical pixels.
  ///
  /// Downloading the 2560px original to paint it 400px wide wastes bandwidth and
  /// is a genuine cause of transfers that never finish on a slow connection. The
  /// largest is only used when nothing reaches the budget.
  MediaRef? refFor(double targetWidth) {
    if (variants.isEmpty) {
      final id = fileId;
      return id == null ? null : MediaRef(fileId: id, remoteId: remoteId);
    }
    final chosen = variants.firstWhere(
      (v) => v.width >= targetWidth,
      orElse: () => variants.last,
    );
    return MediaRef(fileId: chosen.fileId, remoteId: chosen.remoteId);
  }

  bool get isVisual =>
      type == 'photo' || type == 'video' || type == 'animation';

  /// Telegram animations are silent MP4, so they play through the same video
  /// pipeline as video — they are not GIF images.
  bool get isPlayable => type == 'video' || type == 'animation';

  double get aspectRatio {
    final w = width;
    final h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return 16 / 9;
    return w / h;
  }

  static PostMedia? decode(String? json) {
    if (json == null || json.isEmpty) return null;
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) return null;

    final thumb = decoded['thumb'] as String?;

    final rawSizes = decoded['sizes'];
    final variants = <PhotoVariant>[
      if (rawSizes is List)
        for (final size in rawSizes)
          if (size is Map &&
              size['id'] is int &&
              size['w'] is int &&
              (size['w'] as int) > 0)
            PhotoVariant(
              fileId: size['id'] as int,
              width: size['w'] as int,
              remoteId: size['remote'] as String?,
            ),
    ]..sort((a, b) => a.width.compareTo(b.width));

    return PostMedia(
      type: decoded['type'] as String? ?? 'unsupported',
      // TDLib hands the minithumbnail over as base64 in the JSON interface.
      thumbBytes: thumb == null ? null : base64Decode(thumb),
      width: (decoded['w'] ?? decoded['tw']) as int?,
      height: (decoded['h'] ?? decoded['th']) as int?,
      fileId: decoded['fileId'] as int?,
      label: (decoded['name'] ?? decoded['question'] ?? decoded['emoji'])
          as String?,
      variants: variants,
      remoteId: decoded['remote'] as String?,
      byteSize: decoded['bytes'] as int?,
      posterId: decoded['posterId'] as int?,
      posterRemoteId: decoded['posterRemote'] as String?,
      streamable: decoded['streamable'] as bool? ?? false,
    );
  }
}

/// Shows a post's image, upgrading itself from placeholder to full resolution.
///
/// The stored `minithumbnail` renders instantly — it is already in the row, so
/// there is no request and no empty frame. Then, if auto-loading is on, the
/// full-size file is requested through [MediaCache] and crossfaded in when it
/// lands.
///
/// Auto-loading covers **photos only**. Video and animation files are orders of
/// magnitude larger, and pulling them while scrolling is the behaviour the spec
/// warns about for metered connections — those keep tap-to-open. The
/// [AppScope.autoLoadImages] toggle turns even photo auto-loading off.
///
/// Because the feed list is virtualized, "in the tree" is very close to "near the
/// viewport", which is what makes requesting on mount the right trigger.
class PostMediaView extends StatefulWidget {
  const PostMediaView({super.key, required this.media, this.onTap});

  final PostMedia media;
  final VoidCallback? onTap;

  @override
  State<PostMediaView> createState() => _PostMediaViewState();
}

class _PostMediaViewState extends State<PostMediaView> {
  MediaCache? _cache;
  MediaRef? _requested;

  bool get _shouldAutoLoad => widget.media.type == 'photo';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_shouldAutoLoad) return;
    if (!AppScope.autoLoadImagesOf(context)) return;

    // Budget in device pixels: the card spans the window width, so anything wider
    // than that is detail nobody can see.
    final media = MediaQuery.of(context);
    final targetWidth = media.size.width * media.devicePixelRatio;

    final ref = widget.media.refFor(targetWidth);
    if (ref == null || _requested == ref) return;

    final cache = AppScope.mediaCacheOf(context);
    // A changed budget (rotation, resize) can select a different variant; drop the
    // old request so it does not hold a queue slot for a file nobody is showing.
    final previous = _requested;
    if (previous != null) cache.release(previous);
    _cache = cache;
    _requested = ref;
    cache.request(ref);
  }

  @override
  void dispose() {
    final ref = _requested;
    if (ref != null) _cache?.release(ref);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _PostMediaBody(
      media: widget.media,
      onTap: widget.onTap,
      state: _requested == null ? null : _cache?.stateOf(_requested!),
      onRetry: _requested == null ? null : () => _cache?.retry(_requested!),
    );
  }
}

class _PostMediaBody extends StatelessWidget {
  const _PostMediaBody({
    required this.media,
    required this.onTap,
    required this.state,
    required this.onRetry,
  });

  final PostMedia media;
  final VoidCallback? onTap;
  final ValueListenable<MediaState>? state;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!media.isVisual) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(_iconFor(media.type),
                size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                media.label ?? media.type,
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    final thumb = media.thumbBytes;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: GestureDetector(
        onTap: onTap,
        child: AspectRatio(
          aspectRatio: media.aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (thumb != null)
                // Shimmers only while the real file is still arriving, so a
                // placeholder reads as pending rather than as the final image.
                Shimmer(
                  enabled: state != null && !(state!.value.isDone),
                  child: Image.memory(
                  thumb,
                  fit: BoxFit.cover,
                  // The minithumbnail is ~32px wide; letting it scale smoothly
                  // is what makes it read as a blur placeholder rather than a
                  // pixelated mess.
                    filterQuality: FilterQuality.low,
                    gaplessPlayback: true,
                  ),
                )
              else
                ColoredBox(color: theme.colorScheme.surfaceContainerHighest),
              // Full resolution fades in over the placeholder once it arrives.
              // Layering rather than replacing avoids a flash of empty space
              // while the decoder works.
              if (state != null)
                ValueListenableBuilder<MediaState>(
                  valueListenable: state!,
                  builder: (context, value, _) {
                    if (value.isFailed) {
                      return _RetryOverlay(
                        onRetry: onRetry,
                        reason: _reasonOf(value.error),
                      );
                    }
                    final path = value.path;
                    if (path == null) return const SizedBox.shrink();
                    return _FadeInImage(path: path, onGone: onRetry);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _iconFor(String type) => switch (type) {
      'document' => Icons.description_outlined,
      'poll' => Icons.poll_outlined,
      'sticker' => Icons.emoji_emotions_outlined,
      _ => Icons.attachment,
    };

String _reasonOf(Object? error) => switch (error) {
      MediaUnavailableException(:final reason) => reason,
      StateError(:final message) => message,
      null => 'download failed',
      _ => '$error',
    };

/// Explicit terminal state for media that will not load.
///
/// A blur placeholder must never be permanent: it is indistinguishable from a bug
/// and gives the user nothing to do. This does.
class _RetryOverlay extends StatelessWidget {
  const _RetryOverlay({required this.onRetry, required this.reason});

  final VoidCallback? onRetry;
  final String reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ColoredBox(
      color: Colors.black45,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Tap to retry'),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                reason,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Crossfades a decoded file in over the placeholder beneath it.
class _FadeInImage extends StatelessWidget {
  const _FadeInImage({required this.path, this.onGone});

  final String path;

  /// Called when the file cannot be decoded or has vanished from disk, so the
  /// cache can re-fetch instead of leaving a stale path rendering nothing.
  final VoidCallback? onGone;

  @override
  Widget build(BuildContext context) {
    final view = View.of(context);

    // A path is not proof of bytes: TDLib or the OS can evict a cached file after
    // reporting it complete. Checking here catches an eviction that happened after
    // the download resolved.
    if (!File(path).existsSync()) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onGone?.call());
      return const SizedBox.shrink();
    }

    return Image.file(
      File(path),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      // Decode at screen width, not at the source resolution. Channel photos are
      // routinely 1280px+ wide; decoding a column of them at full size is what
      // drops frames while scrolling and what pushes the image cache over its
      // budget.
      cacheWidth: view.physicalSize.width.round().clamp(360, 1440),
      // `frameBuilder` fires once the frame is actually decoded, so the fade
      // tracks readiness rather than the download finishing.
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: child,
        );
      },
      // A file TDLib reports as complete can still fail to decode — truncated,
      // or evicted between the check above and the read. Ask for it again rather
      // than leaving the placeholder to sit there.
      errorBuilder: (context, error, stack) {
        WidgetsBinding.instance.addPostFrameCallback((_) => onGone?.call());
        return const SizedBox.shrink();
      },
    );
  }
}
