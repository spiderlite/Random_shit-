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
                      Text('Allow phone connections', style: context.text.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        'Phones and browsers on the same Wi-Fi can send downloads to this computer.',
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

    // Plain rows inside the existing card: no box-in-a-box.
    return FutureBuilder<List<String>>(
      future: io.lanAddresses(),
      builder: (context, snap) {
        final addrs = snap.data ?? const [];
        final first = addrs.isEmpty ? null : '${addrs.first}:$remoteDefaultPort';
        Widget row(String label, Widget value, {Widget? trailing}) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
              child: Row(
                children: [
                  SizedBox(width: 72, child: Text(label, style: context.text.labelMedium)),
                  Expanded(child: value),
                  ?trailing,
                ],
              ),
            );
        final big = context.mono.copyWith(fontSize: 17, color: p.ink, fontWeight: FontWeight.w500);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Divider(color: p.line, indent: 16, endIndent: 16),
            row(
              'Address',
              snap.connectionState != ConnectionState.done
                  ? const Align(alignment: Alignment.centerLeft, child: Spinner(size: 14))
                  : addrs.isEmpty
                      ? Text('No network found. Connect this computer to Wi-Fi.', style: context.text.bodyMedium)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [for (final a in addrs.take(3)) _Copyable(text: '$a:$remoteDefaultPort', style: big)],
                        ),
            ),
            row(
              'Code',
              _Copyable(text: code, style: big.copyWith(fontSize: 22, letterSpacing: 2, color: p.accent)),
              trailing: HaulButton(
                label: 'New code',
                dense: true,
                tone: ButtonTone.ghost,
                tooltip: 'Phones using the old code will need the new one',
                onPressed: app.newServerCode,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text(
                first == null
                    ? 'Then enter the address and code in the Haul app on your phone.'
                    : 'Enter these in the Haul app on your phone, or open http://$first in any phone browser and enter the code.',
                style: context.text.bodySmall,
              ),
            ),
          ],
        );
      },
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
