import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/remote_protocol.dart';
import '../../platform/io.dart' as io;
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../widgets/kit.dart';
import '../widgets/toast.dart';

/// Computer side of remote mode: switch it on, read off the address and
/// code, type them on the phone. Nothing else to configure.
class PhoneAccess extends StatelessWidget {
  const PhoneAccess({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = context.palette;
    final on = app.settings.serverEnabled;
    final running = app.serverRunning;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Pressable(
          onTap: () => app.setServerEnabled(!on),
          pressScale: 1,
          borderRadius: BorderRadius.circular(Radii.lg),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Use Haul from your phone', style: context.text.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        'iPhones, Android phones and any browser on your Wi-Fi can add downloads here.',
                        style: context.text.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Switch(value: on, onChanged: app.setServerEnabled),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: Motion.normal,
          curve: Motion.ease,
          alignment: Alignment.topCenter,
          child: !on
              ? const SizedBox(width: double.infinity)
              : app.serverError != null
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Text(app.serverError!, style: context.text.bodySmall!.copyWith(color: p.danger)),
                    )
                  : !running
                      ? const Padding(padding: EdgeInsets.all(16), child: Center(child: Spinner()))
                      : const _Details(),
        ),
      ],
    );
  }
}

class _Details extends StatelessWidget {
  const _Details();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = context.palette;
    final code = app.serverCode;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Appear(
        offset: 6,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: p.sunken, borderRadius: BorderRadius.circular(Radii.md)),
          child: FutureBuilder<List<String>>(
            future: io.lanAddresses(),
            builder: (context, snap) {
              final addrs = snap.data ?? const [];
              final first = addrs.isEmpty ? null : '${addrs.first}:$remoteDefaultPort';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ADDRESS', style: context.text.labelSmall!.copyWith(letterSpacing: 0.8)),
                  const SizedBox(height: 4),
                  if (snap.connectionState != ConnectionState.done)
                    const Spinner(size: 14)
                  else if (addrs.isEmpty)
                    Text('No network found. Connect this computer to Wi-Fi.', style: context.text.bodyMedium)
                  else
                    for (final a in addrs.take(3))
                      _Copyable(text: '$a:$remoteDefaultPort', style: context.text.titleMedium!),
                  const SizedBox(height: 14),
                  Text('CODE', style: context.text.labelSmall!.copyWith(letterSpacing: 0.8)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _Copyable(
                        text: code,
                        style: context.text.headlineSmall!.copyWith(letterSpacing: 5, color: p.accent),
                      ),
                      const Spacer(),
                      HaulButton(
                        label: 'New code',
                        dense: true,
                        tone: ButtonTone.ghost,
                        icon: Icons.refresh_rounded,
                        tooltip: 'Phones using the old code will need the new one',
                        onPressed: app.newServerCode,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    first == null
                        ? 'Then open the Haul app on your phone and enter the address and code.'
                        : 'On your phone: open the Haul app and enter these — or simply visit http://$first in any browser.',
                    style: context.text.bodySmall,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Copyable extends StatelessWidget {
  const _Copyable({required this.text, required this.style});
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Pressable(
        tooltip: 'Copy',
        pressScale: 0.98,
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          Clipboard.setData(ClipboardData(text: text));
          ToastHost.show(context, 'Copied $text', icon: Icons.copy_rounded);
        },
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(text, style: style),
      );
}
