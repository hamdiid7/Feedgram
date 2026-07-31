import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../app_scope.dart';
import 'post_media.dart';

/// Full-size media, downloaded on open.
///
/// Shows the stored `minithumbnail` blurred underneath while the real file
/// streams in, so there is never an empty frame — the placeholder is already in
/// the database, so it appears instantly.
class MediaViewer extends StatefulWidget {
  const MediaViewer({super.key, required this.media, this.caption});

  final PostMedia media;
  final String? caption;

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  String? _localPath;
  double _progress = 0;
  Object? _error;
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    final fileId = widget.media.fileId;
    if (fileId == null) return;

    AppScope.mediaOf(context).download(fileId).listen(
      (download) {
        if (!mounted) return;
        setState(() {
          _progress = download.progress;
          _localPath = download.localPath;
        });
      },
      onError: (Object e) {
        if (mounted) setState(() => _error = e);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final thumb = widget.media.thumbBytes;
    final path = _localPath;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(_error != null
            ? 'Download failed'
            : path != null
                ? ''
                : '${(_progress * 100).round()}%'),
      ),
      body: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (thumb != null && path == null)
              Image.memory(thumb, fit: BoxFit.contain, filterQuality: FilterQuality.low),
            if (path != null && widget.media.isPlayable)
              // Fullscreen is the only place sound plays. The coordinator has
              // released every inline decoder by now, so this player has the
              // budget to itself.
              _FullscreenVideo(path: path, loop: widget.media.type == 'animation')
            else if (path != null)
              InteractiveViewer(
                maxScale: 5,
                child: Image.file(File(path), fit: BoxFit.contain),
              )
            else if (_error == null)
              CircularProgressIndicator(
                value: _progress > 0 ? _progress : null,
                color: Colors.white,
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text('$_error',
                    style: const TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center),
              ),
          ],
        ),
      ),
    );
  }
}

/// Fullscreen playback with sound and standard controls.
///
/// Animations loop silently because that is what they are; video plays once with
/// audio, which is the whole point of tapping through from the muted inline view.
class _FullscreenVideo extends StatefulWidget {
  const _FullscreenVideo({required this.path, required this.loop});

  final String path;
  final bool loop;

  @override
  State<_FullscreenVideo> createState() => _FullscreenVideoState();
}

class _FullscreenVideoState extends State<_FullscreenVideo> {
  VideoPlayerController? _controller;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final controller = VideoPlayerController.file(File(widget.path));
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(widget.loop);
      await controller.setVolume(widget.loop ? 0 : 1);
      await controller.play();
      setState(() => _controller = controller);
    } catch (e) {
      await controller.dispose();
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    // Releasing the decoder here is what lets inline playback resume; leaving it
    // alive would also keep the audio session open behind the feed.
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Playback failed: $_error',
            style: const TextStyle(color: Colors.white70),
            textAlign: TextAlign.center),
      );
    }

    final controller = _controller;
    if (controller == null) {
      return const CircularProgressIndicator(color: Colors.white);
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
        if (!widget.loop) ...[
          VideoProgressIndicator(controller, allowScrubbing: true),
          _Controls(controller: controller),
        ],
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              color: Colors.white,
              icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
              onPressed: () =>
                  value.isPlaying ? controller.pause() : controller.play(),
            ),
            IconButton(
              color: Colors.white,
              icon: Icon(value.volume == 0 ? Icons.volume_off : Icons.volume_up),
              onPressed: () => controller.setVolume(value.volume == 0 ? 1 : 0),
            ),
            Text(
              '${_clock(value.position)} / ${_clock(value.duration)}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        );
      },
    );
  }
}

String _clock(Duration d) {
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
