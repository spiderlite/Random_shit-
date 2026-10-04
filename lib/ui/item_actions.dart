import 'package:flutter/material.dart';

import '../core/models.dart';
import '../platform/info.dart';
import '../state/app_state.dart';
import 'widgets/toast.dart';

/// Where a finished file can be reached *from this device*.
enum Reach {
  /// On this device: open, share, reveal.
  here,
  /// On the computer (remote mode); can be copied over.
  computer,
  /// In a browser: can be downloaded.
  browser,
  none,
}

Reach reachOf(AppState app, DownloadItem item) {
  if (item.status != DownloadStatus.done || item.filePath == null) return Reach.none;
  if (app.remote == null) return Reach.here;
  if (isWeb) return Reach.browser;
  return item.localPath != null ? Reach.here : Reach.computer;
}

String? localFileOf(AppState app, DownloadItem item) => app.remote == null ? item.filePath : item.localPath;

/// The one "give me my video" action, whatever the setup.
Future<void> openItem(BuildContext context, DownloadItem item) async {
  final app = AppScope.read(context);
  final toast = ToastHost.of(context);
  switch (reachOf(app, item)) {
    case Reach.here:
      final ok = await app.bridge.openFile(localFileOf(app, item)!, contentUri: item.contentUri);
      if (!ok) toast?.show(ToastData('Couldn\'t open it — was the file moved?', icon: Icons.error_outline_rounded));
    case Reach.computer:
      toast?.show(ToastData('Copying to this phone…', icon: Icons.download_rounded));
      final ok = await app.queue.saveToDevice(item.id);
      if (!ok) {
        toast?.show(ToastData('Couldn\'t copy it. Is your computer still on?', icon: Icons.error_outline_rounded));
      } else if (item.localPath != null) {
        await app.bridge.openFile(item.localPath!, contentUri: item.contentUri);
      }
    case Reach.browser:
      final remote = app.remote!;
      final path = item.filePath!;
      await app.bridge.downloadInBrowser(remote.fileUri(path), path.split(remote.pathSeparator).last);
    case Reach.none:
      break;
  }
}

IconData openIcon(AppState app, DownloadItem item) => switch (reachOf(app, item)) {
      Reach.here => item.isAudio ? Icons.headphones_rounded : Icons.play_arrow_rounded,
      Reach.computer || Reach.browser => Icons.download_rounded,
      Reach.none => Icons.play_arrow_rounded,
    };

String openLabel(AppState app, DownloadItem item) => switch (reachOf(app, item)) {
      Reach.here => item.isAudio ? 'Play' : 'Open',
      Reach.computer => 'Save to phone',
      Reach.browser => 'Download',
      Reach.none => 'Open',
    };
