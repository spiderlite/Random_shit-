/// The computer side of remote mode, as the rest of the app sees it. The
/// real server ([RemoteServer]) needs `dart:io`, so shared code only ever
/// holds this interface.
abstract class RemoteHost {
  bool get running;
  Future<void> start();
  Future<void> stop();
}
