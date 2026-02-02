import 'dart:io';

bool isSupportedPlatform() {
  // Allow all platforms during tests
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return true;
  }
  // Support iOS, Android, macOS, and HarmonyOS
  // Exclude Linux and Windows desktop platforms
  return !(Platform.isLinux || Platform.isWindows);
}
