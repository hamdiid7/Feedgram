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
/// player; the difference is that animations are small, always muted, and looped,
/// while videos are size-gated and can be opened fullscreen with sound.
///
/// The controller is created **only** while [PlaybackCoordinator] grants this
/// item a slot, and disposed the moment the grant is withdrawn. That is what keeps
/// the number of live decoders bounded no matter how fast the feed scrolls.
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

  /// Above this, a video is never downloaded or autoplayed — it shows a
  /// thumbnail with tap-to-play instead. Autoplaying a 50 MB clip while scrolling
  /// is exactly the runaway data use the spec warns about.
  static const autoplayByteLimit = 10 * 1024 * 1024;

  @override
  State<PostVideoView> createState() => _PostVideoViewState();
}

class _PostVideoViewState extends State<PostVideoView> {
  VideoPlayerController? _controller;
  PlaybackCoordinator? _coordinator;
  MediaCache? _cache;
  MediaRef? _ref;

  var _initialising = false;

  bool get _granted => _coordinator?.isGranted(widget.postKey) ?? false;

  /// GIFs are small and silent, so they behave like images: fetched eagerly and
  /// looped whenever they get a slot.
  bool get _isAnimation => widget.media.type == 'animation';

  /// Videos above the limit are strictly tap-to-play.
  bool get _mayAutoplay =>
      _isAnimation || (widget.media.byteSize ?? 0) <= PostVideoView.autoplayByteLimit;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _coordinator?.removeListener(_onGrantChanged);
    _coordinator = AppScope.playbackOf(context)..addListener(_onGrantChanged);
    _cache = AppScope.mediaCacheOf(context);

    // Only fetch what could actually play. A large video is left alone until the
    // user asks for it.
    if (_mayAutoplay && AppScope.autoLoadImagesOf(context)) {
      final ref = widget.media.refFor(double.infinity);
      if (ref != null && _ref != ref) {
        _detachMediaListener();
        _ref = ref;
        // Playback usually loses the race against the download: the slot is
        // granted while the file is still arriving. Without listening for the
        // file, `_ensurePlaying` bails on a null path and nothing ever tries
        // again — which presents exactly as "video never autoplays".
        _mediaState = _cache!.stateOf(ref)..addListener(_onMediaChanged);
        _cache!.request(ref);
      }
    }
  }

  ValueListenable<MediaState>? _mediaState;

  void _detachMediaListener() {
    _mediaState?.removeListener(_onMediaChanged);
    _mediaState = null;
  }

  void _onMediaChanged() {
    if (!mounted) return;
    if (_coordinator?.isGranted(widget.postKey) ?? false) _ensurePlaying();
  }

  void _onGrantChanged() {
    final granted = _coordinator?.isGranted(widget.postKey) ?? false;
    if (granted) {
      _ensurePlaying();
    } else {
      _teardown();
    }
  }

  /// Why playback has not started, for the debug overlay. A silent failure here
  /// is indistinguishable from "autoplay is broken", which cost real time to
  /// diagnose once already.
  String? _blocked;

  Future<void> _ensurePlaying() async {
    if (_controller != null || _initialising || !_mayAutoplay) return;

    final ref = _ref;
    if (ref == null) {
      _note('no file reference');
      return;
    }
    final path = _cache?.stateOf(ref).value.path;
    // Autoplay requires the file on disk; streaming a partial file is what
    // produces decoder errors.
    if (path == null) {
      _note('waiting for download');
      return;
    }
    if (!File(path).existsSync()) {
      _note('file missing on disk');
      return;
    }

    _initialising = true;
    final controller = VideoPlayerController.file(File(path));

    try {
      await controller.initialize();
      // The grant can be withdrawn while initialize() is in flight — scrolling is
      // faster than decoder setup. Without this check the player would leak.
      if (!mounted || !(_coordinator?.isGranted(widget.postKey) ?? false)) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(true);
      // Inline playback is always silent, video included. Sound only ever starts
      // from an explicit tap into fullscreen.
      await controller.setVolume(0);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _blocked = null;
      });
    } catch (e) {
      await controller.dispose();
      // Emulators in particular fail to initialise hardware decoders; on a real
      // device this is where a genuinely unplayable file shows up.
      debugPrint('[playback] initialize failed for ${widget.postKey}: $e');
      if (mounted) {
        setState(() {
          _blocked = 'decoder failed: $e';
        });
      }
    } finally {
      _initialising = false;
    }
  }

  void _note(String reason) {
    if (_blocked == reason || !mounted) return;
    setState(() => _blocked = reason);
  }

  void _teardown() {
    final controller = _controller;
    if (controller == null) return;
    setState(() => _controller = null);
    // pause before dispose so the decoder is released promptly rather than at the
    // end of the frame.
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

    return VisibilityDetector(
      key: ValueKey('playback:${widget.postKey}'),
      onVisibilityChanged: (info) {
        if (!mounted) return;
        _coordinator?.report(widget.postKey, info.visibleFraction);
        // A newly granted item may already have its file; the grant listener only
        // fires on change, so poke it here too.
        if (_coordinator?.isGranted(widget.postKey) ?? false) _ensurePlaying();
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
                // The still frame stays mounted underneath: swapping it out for the
                // player would flash empty space on every grant change.
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
                if (controller == null || !_mayAutoplay)
                  _PlayBadge(
                    label: _isAnimation
                        ? 'GIF'
                        : _mayAutoplay
                            ? null
                            : _sizeLabel(widget.media.byteSize),
                  ),
                if (!_isAnimation && controller != null)
                  const Positioned(
                    right: 8,
                    bottom: 8,
                    child: _MutedBadge(),
                  ),
                // Debug-only: says *why* a playable post is not playing. Without
                // this the three distinct causes — no grant, no file, dead
                // decoder — all look identical on screen.
                if (kDebugMode && controller == null && _blocked != null)
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        child: Text(
                          _granted ? _blocked! : 'no slot · $_blocked',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 10),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
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

class _PlayBadge extends StatelessWidget {
  const _PlayBadge({this.label});

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
          padding: EdgeInsets.symmetric(horizontal: label == null ? 10 : 14, vertical: 10),
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

/// Inline video is muted, so say so — otherwise a silent clip reads as broken.
class _MutedBadge extends StatelessWidget {
  const _MutedBadge();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      child: Padding(
        padding: EdgeInsets.all(6),
        child: Icon(Icons.volume_off, color: Colors.white, size: 14),
      ),
    );
  }
}
