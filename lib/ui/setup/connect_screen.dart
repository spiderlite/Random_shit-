import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../platform/info.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../widgets/kit.dart';

/// iOS and the web: Haul here is the remote control, Haul on a computer
/// does the downloading. Pair once with the address and a 6-letter code.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _host = TextEditingController();
  final _code = TextEditingController();
  final _codeFocus = FocusNode();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = AppScope.read(context).settings;
    _host.text = s.remoteHost ?? '';
  }

  @override
  void dispose() {
    _host.dispose();
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final app = AppScope.read(context);
    if (!isWeb && _host.text.trim().isEmpty) {
      setState(() => _error = 'Type the address Haul shows on your computer.');
      return;
    }
    if (_code.text.replaceAll(RegExp(r'\s'), '').length < 6) {
      setState(() => _error = 'The code has 6 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await app.connect(_host.text, _code.text);
    if (!mounted) return;
    if (err != null) HapticFeedback.heavyImpact();
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final app = AppScope.of(context);

    InputDecoration deco(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: context.text.bodyLarge!.copyWith(color: p.ink3),
      filled: true,
      fillColor: p.sunken,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.md), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: BorderSide(color: p.accent.withValues(alpha: 0.6), width: 1.5),
      ),
    );

    Widget step(String n, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: p.sunken, shape: BoxShape.circle),
            child: Text(
              n,
              style: context.text.labelSmall!.copyWith(color: p.ink2, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: context.text.bodyMedium)),
        ],
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(alignment: Alignment.centerLeft, child: HaulMark(size: 40)),
                    const SizedBox(height: 26),
                    Text(isWeb ? 'Enter your code' : 'Connect to your computer', style: context.text.displaySmall),
                    const SizedBox(height: 10),
                    Text(
                      isWeb
                          ? 'Downloads run on ${app.webOrigin?.host ?? 'the computer'} and you can save them to this device. Enter the code shown in Haul on that computer.'
                          : 'Haul on this phone sends downloads to your computer, then copies the videos back here. '
                                'Both need to be on the same Wi-Fi.',
                      style: context.text.bodyLarge!.copyWith(color: p.ink2),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                      decoration: BoxDecoration(
                        color: p.surface,
                        borderRadius: BorderRadius.circular(Radii.lg),
                        border: Border.all(color: p.line),
                      ),
                      child: Column(
                        children: [
                          step('1', 'Open Haul on your Mac, Windows or Linux computer'),
                          step('2', 'In Settings, turn on Allow phone connections'),
                          step('3', isWeb ? 'Type the 6-letter code it shows' : 'Type the address and code it shows'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    if (!isWeb) ...[
                      Text('Address', style: context.text.labelMedium),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _host,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => _codeFocus.requestFocus(),
                        style: context.mono.copyWith(fontSize: 16, color: p.ink),
                        decoration: deco('192.168.1.20'),
                      ),
                      const SizedBox(height: 14),
                    ],
                    Text('Code', style: context.text.labelMedium),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _code,
                      focusNode: _codeFocus,
                      autofocus: isWeb,
                      autocorrect: false,
                      enableSuggestions: false,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 7,
                      textInputAction: TextInputAction.go,
                      onSubmitted: (_) => _connect(),
                      style: context.mono.copyWith(
                        fontSize: 24,
                        letterSpacing: 4,
                        color: p.ink,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: deco('K7P2QX').copyWith(counterText: ''),
                    ),
                    AnimatedSize(
                      duration: Motion.normal,
                      curve: Motion.ease,
                      child: _error == null
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.error_outline_rounded, size: 17, color: p.danger),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(_error!, style: context.text.bodyMedium!.copyWith(color: p.danger)),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    const SizedBox(height: 20),
                    HaulButton(
                      label: _busy ? 'Connecting…' : 'Connect',
                      tone: ButtonTone.primary,
                      expand: true,
                      loading: _busy,
                      onPressed: _busy ? null : _connect,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
