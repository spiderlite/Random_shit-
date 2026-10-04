import 'package:flutter/material.dart';

import '../../core/links.dart';
import '../../platform/io.dart' as io;
import '../../theme/theme.dart';

/// 16:9 thumbnail that fades in when loaded and falls back to a quiet tile
/// with the site's initial (never a broken-image icon).
class VideoThumb extends StatelessWidget {
  static ImageProvider _provider(String url) {
    // Local files (e.g. thumbnails yt-dlp wrote next to a download).
    if (url.startsWith('/') || url.startsWith('file://')) {
      final local = io.localImage(url);
      if (local != null) return local;
    }
    return NetworkImage(url);
  }

  const VideoThumb({super.key, required this.url, required this.link, this.width = 112, this.audio = false, this.radius = 10});

  final String? url;
  final String link;
  final double width;
  final bool audio;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final h = width * 9 / 16;
    final site = detectSite(link);
    final fallback = Container(
      color: p.sunken,
      alignment: Alignment.center,
      child: Icon(
        audio ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded,
        size: width * 0.22,
        color: p.ink3,
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: h,
        child: Stack(
          fit: StackFit.expand,
          children: [
            fallback,
            if (url != null)
              Image(
                // Decode at display size: a long queue stays light on memory.
                image: ResizeImage.resizeIfNeeded(
                  (width * MediaQuery.devicePixelRatioOf(context)).round(),
                  null,
                  _provider(url!),
                ),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
                frameBuilder: (_, child, frame, sync) => sync
                    ? child
                    : AnimatedOpacity(
                        opacity: frame == null ? 0 : 1,
                        duration: Motion.normal,
                        curve: Motion.easeOut,
                        child: child,
                      ),
              ),
            if (url == null && site.key != 'generic' && site.key != 'unknown')
              Positioned(
                left: 6,
                bottom: 5,
                child: Text(
                  site.label,
                  style: context.text.labelSmall!.copyWith(color: p.ink3, fontSize: 9.5),
                ),
              ),
            // Hairline inner border keeps light thumbnails from bleeding
            // into the background.
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: p.ink.withValues(alpha: 0.06)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
