/// Everything that touches files, processes or the window, behind one
/// import that works on native platforms and the web alike.
library;

export 'io_native.dart' if (dart.library.js_interop) 'io_web.dart';
