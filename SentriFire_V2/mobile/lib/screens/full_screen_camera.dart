import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/app_models.dart';
import '../theme/app_theme.dart';
import '../widgets/status_widgets.dart';

class FullScreenCamera extends StatefulWidget {
  const FullScreenCamera({super.key, required this.camera});
  final CameraStatus camera;

  @override
  State<FullScreenCamera> createState() => _FullScreenCameraState();
}

class _FullScreenCameraState extends State<FullScreenCamera> {
  VideoPlayerController? player;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _openStream();
  }

  Future<void> _openStream() async {
    final String? url = widget.camera.streamUrl;
    if (!widget.camera.online || url == null || url.isEmpty) {
      setState(() {
        loading = false;
        error = widget.camera.connectionMessage ?? 'This camera is offline.';
      });
      return;
    }
    final VideoPlayerController next = VideoPlayerController.networkUrl(
      Uri.parse(url),
      formatHint: VideoFormat.hls,
    );
    try {
      await next.initialize();
      await next.setLooping(true);
      await next.play();
      if (!mounted) {
        await next.dispose();
        return;
      }
      setState(() {
        player = next;
        loading = false;
      });
    } catch (exception) {
      await next.dispose();
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Live stream unavailable: $exception';
        });
      }
    }
  }

  @override
  void dispose() {
    player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color color = levelColor(widget.camera.level);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Center(
                child: loading
                    ? const CircularProgressIndicator()
                    : player != null && player!.value.isInitialized
                        ? AspectRatio(aspectRatio: player!.value.aspectRatio, child: VideoPlayer(player!))
                        : _fallback(color),
              ),
            ),
            Positioned(
              left: 8,
              right: 12,
              top: 4,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    style: IconButton.styleFrom(backgroundColor: Colors.black54),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.camera.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text(widget.camera.location, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color),
                    ),
                    child: Text(levelLabel(widget.camera.level), style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 18,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xDD071018),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: color),
                ),
                child: Row(
                  children: [
                    Icon(levelIcon(widget.camera.level), color: color, size: 31),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Detection confidence ${(widget.camera.confidence * 100).toStringAsFixed(0)}%',
                            style: TextStyle(color: color, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 3),
                          const Text('Confidence is not fire severity.', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                    if (player != null)
                      IconButton(
                        onPressed: () {
                          setState(() {
                            player!.value.isPlaying ? player!.pause() : player!.play();
                          });
                        },
                        icon: Icon(player!.value.isPlaying ? Icons.pause : Icons.play_arrow),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallback(Color color) => Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_outlined, color: color, size: 70),
            const SizedBox(height: 14),
            Text(error ?? 'Live stream unavailable.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () {
                setState(() {
                  loading = true;
                  error = null;
                });
                _openStream();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Detection and local alarm processing continue on the Raspberry Pi.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ],
        ),
      );
}
