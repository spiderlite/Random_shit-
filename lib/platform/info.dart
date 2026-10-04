import 'package:flutter/foundation.dart';

/// Platform checks that also compile for the web (unlike `dart:io`'s
/// `Platform`).
bool get isWeb => kIsWeb;
bool get isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
bool get isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
bool get isMacOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
bool get isWindows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
bool get isLinux => !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;
bool get isDesktop => isMacOS || isWindows || isLinux;

/// Phones and tablets — touch-first layouts and share-sheet flows.
bool get isHandheld =>
    defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
