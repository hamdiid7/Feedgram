import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../data/media_cache.dart';
import '../app_scope.dart';
import 'playback_coordinator.dart';
import 'post_media.dart';

/// Inline video and GIF playback.
///
/// Telegram "animations" are silent MP4, not GIF, so both go through the same
/// player; the difference is that animations are small and always muted, while
/// videos are size-gated and can be opened fullscreen with sound.
///
/// Three behaviours worth spelling out:
///
/// * **A paused video shows its poster frame, not a blur.** Scrolling past simply
///   stops playback — no pause icon, no placeholder swap. The poster is a real
///   JPEG from TDLib rather than the 32px minithumbnail, which is what used to make
///   a stopped video look out of focus.
/// * **Playback starts on a partial file.** Waiting for a complete download meant
///   staring at a still image for the length of the transfer; now it begins once
///   enough of the front of the file exists to decode.
/// * **While there is nothing to show yet, a spinner** — never a permanent
///   placeholder pretending to be content.
///
/// The controller exists only while [PlaybackCoordinator] grants this item a slot,
/// which is what keeps live decoders bounded however fast the feed scrolls.
class PostVideoView extends StatefulWidget {
  const PostVideoView({
    super.key,
    required this.media,
    required this.postKey,
    this.onTap,
  });

  final PostMedia media;

  /// Stable identity for this post, used as the coordinator's slot key.
  final String postKey;

  final VoidCallback? onTap;

  /// Above this, a video is never downloaded or autoplayed — it shows a poster
  /// with tap-to-play instead. Autoplaying a 50 MB clip while scrolling is exactly
  /// the runaway data use the spec warns about.
  static const autoplayByteLimit = 10 * 1024 * 1024;

  @override
  State<PostVideoView> createState() => _PostVideoViewState();
}

class _PostVideoViewState extends State<PostVideoView> {
  VideoPlayerController? _controller;
  PlaybackCoordinator? _coordinator;
  MediaCache? _cache;
  MediaRef? _ref;
  MediaRef? _posterRef;
  ValueListenable<MediaState>? _mediaState;

  var _initialising = false;

  /// Path the current controller was built on. Kept so a controller started on a
  /// partial file can be rebuilt once the complete one lands.
  String? _openedPath;
  var _openedPartial = false;

  bool get _granted => _coordinator?.isGranted(widget.postKey) ?? false;
  bool get _isAnimation => widget.media.type == 'animation';

  bool get _mayAutoplay =>
      _isAnimation ||
      (widget.media.byteSize ?? 0) <= PostVideoView.autoplayByteLimit;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _coordinator?.removeListener(_onGrantChanged);
    _coordinator = AppScope.playbackOf(context)..addListener(_onGrantChanged);
    final cache = AppScope.mediaCacheOf(context);
    _cache = cache;

    // The poster is small and always worth having: it is what the card shows
    // whenever playback is not running.
    final poster = widget.media.posterRef;
    if (poster != null && _posterRef != poster) {
      _posterRef = poster;
      cache.request(poster);
    }

    if (_mayAutoplay && AppScope.autoLoadImagesOf(context)) {
      final ref = widget.media.refFor(double.infinity);
      if (ref != null && _ref != ref) {
        _detachMediaListener();
        _ref = ref;
        // Playback usually loses the race against the download, so the file has to
        // be watched. Without this, `_ensurePlaying` bails on a null path and
        // nothing ever tries again.
        _mediaState = cache.stateOf(ref)..addListener(_onMediaChanged);
        cache.request(ref);
      }
    }
  }

  void _detachMediaListener() {
    _mediaState?.removeListener(_onMediaChanged);
    _mediaState = null;
  }

  void _onMediaChanged() {
    if (!mounted) return;
    if (_granted) _ensurePlaying();
  }

  void _onGrantChanged() {
    if (_granted) {
      _ensurePlaying();
    } else {
      _pause();
    }
  }

  /// Best path to play right now: the complete file if it exists, otherwise a
  /// prefix long enough to decode.
  ({String path, bool partial})? _playablePath() {
    final ref = _ref;
    if (ref == null) return null;
    final state = _cache?.stateOf(ref).value;
    if (state == null) return null;

    final complete = state.path;
    if (complete != null && File(complete).existsSync()) {
      return (path: complete, partial: false);
    }

    // Only files TDLib marks streamable have their moov atom at the front; for the
    // rest a prefix is undecodable and trying wastes a decoder init.
    if (!widget.media.streamable && !_isAnimation) return null;

    final partial = state.partialPath;
    if (state.hasPlayablePrefix && partial != null && File(partial).existsSync()) {
      return (path: partial, partial: true);
    }
    return null;
  }

  Future<void> _ensurePlaying() async {
    if (_initialising || !_mayAutoplay) return;

    final target = _playablePath();
    if (target == null) return;

    // Already playing this exact file, and not on a partial that has since
    // completed.
    if (_controller != null &&
        _openedPath == target.path &&
        !(_openedPartial && !target.partial)) {
      if (!_controller!.value.isPlaying) await _controller!.play();
      return;
    }

    // The complete file arrived while a partial was playing: rebuild on it and
    // resume where it was, so buffering is invisible rather than a restart.
    final resumeAt = _openedPartial && !target.partial
        ? _controller?.value.position
        : null;

    _initialising = true;
    final previous = _controller;
    final controller = VideoPlayerController.file(File(target.path));

    try {
      await controller.initialize();
      if (!mounted || !_granted) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(true);
      // Inline playback is always silent, video included. Sound only ever starts
      // from an explicit tap into fullscreen.
      await controller.setVolume(0);
      if (resumeAt != null) await controller.seekTo(resumeAt);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _openedPath = target.path;
        _openedPartial = target.partial;
      });
      // Swapped only after the replacement is running, so there is no gap.
      await previous?.dispose();
    } catch (e) {
      await controller.dispose();
      debugPrint('[playback] initialize failed for ${widget.postKey}: $e');
    } finally {
      _initialising = false;
    }
  }

  /// Stops playback without tearing the frame down.
  ///
  /// The controller *is* disposed — the decoder budget requires it — but the poster
  /// underneath is a real frame, so the card keeps looking like the video rather
  /// than reverting to a blur.
  void _pause() {
    final controller = _controller;
    if (controller == null) return;
    setState(() {
      _controller = null;
      _openedPath = null;
      _openedPartial = false;
    });
    controller.pause().whenComplete(controller.dispose);
  }

  @override
  void dispose() {
    _detachMediaListener();
    _coordinator?.removeListener(_onGrantChanged);
    _coordinator?.forget(widget.postKey);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final poster = _posterRef;

    return VisibilityDetector(
      key: ValueKey('playback:${widget.postKey}'),
      onVisibilityChanged: (info) {
        if (!mounted) return;
        _coordinator?.report(widget.postKey, info.visibleFraction);
        if (_granted) _ensurePlaying();
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AspectRatio(
          aspectRatio: widget.media.aspectRatio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Poster underneath at all times. It is what a stopped video shows,
                // and it stops the player's first frame arriving over blank space.
                if (poster != null)
                  _Poster(
                    state: _cache!.stateOf(poster),
                    fallback: widget.media.thumbBytes,
                  )
                else
                  PostMediaView(media: widget.media, onTap: widget.onTap),

                if (controller != null)
                  FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: controller.value.size.width,
                      height: controller.value.size.height,
                      child: VideoPlayer(controller),
                    ),
                  ),

                // A spinner only while there is genuinely nothing playable yet.
                // Deliberately no pause icon: a stopped video should read as a
                // still frame, not as a control waiting to be pressed.
                if (controller == null && _mayAutoplay && _ref != null)
                  _LoadingVeil(state: _cache!.stateOf(_ref!)),

                // Oversized videos never autoplay, so they keep an explicit
                // affordance.
                if (!_mayAutoplay)
                  _TapToPlay(label: _sizeLabel(widget.media.byteSize)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sharp poster frame, falling back to the inline minithumbnail until it arrives.
class _Poster extends StatelessWidget {
  const _Poster({required this.state, required this.fallback});

  final ValueListenable<MediaState> state;
  final Uint8List? fallback;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MediaState>(
      valueListenable: state,
      builder: (context, value, _) {
        final path = value.path;
        if (path != null && File(path).existsSync()) {
          return Image.file(File(path), fit: BoxFit.cover, gaplessPlayback: true);
        }
        if (fallback != null) {
          return Image.memory(
            fallback!,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
            gaplessPlayback: true,
          );
        }
        return ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest);
      },
    );
  }
}

/// Circular progress over the poster while the file is still arriving.
class _LoadingVeil extends StatelessWidget {
  const _LoadingVeil({required this.state});

  final ValueListenable<MediaState> state;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MediaState>(
      valueListenable: state,
      builder: (context, value, _) {
        if (value.isDone) return const SizedBox.shrink();

        return Center(
          child: SizedBox(
            height: 34,
            width: 34,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.white,
              backgroundColor: Colors.white24,
              // Determinate once there is a size to measure against, so a slow
              // transfer visibly moves instead of spinning forever.
              value: value.progress > 0 ? value.progress : null,
            ),
          ),
        );
      },
    );
  }
}

class _TapToPlay extends StatelessWidget {
  const _TapToPlay({this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.play_arrow, color: Colors.white),
              if (label != null) ...[
                const SizedBox(width: 6),
                Text(label!,
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String? _sizeLabel(int? bytes) {
  if (bytes == null || bytes <= 0) return null;
  final mb = bytes / (1024 * 1024);
  return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
}
