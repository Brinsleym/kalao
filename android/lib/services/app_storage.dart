import 'dart:io';

import 'package:path/path.dart' as p;

/// App-private folders (DATA_MODEL.md §2 "Files"). Imported audio lives in
/// `media/<sha256>.<ext>` so backups, stems and restore never depend on SAF
/// permissions.
class AppStorage {
  AppStorage(this.root);

  final Directory root;

  Directory get media => Directory(p.join(root.path, 'media'));
  Directory get covers => Directory(p.join(root.path, 'covers'));
  Directory get fonts => Directory(p.join(root.path, 'fonts'));
  Directory get importStaging => Directory(p.join(root.path, 'import_staging'));

  String get libraryDb => p.join(root.path, 'databases', 'kalao_library.db');
  String get historyDb => p.join(root.path, 'databases', 'kalao_history.db');
  String get appStateDb => p.join(root.path, 'databases', 'kalao_app_state.db');

  Future<void> ensure() async {
    for (final dir in [
      media,
      covers,
      fonts,
      importStaging,
      Directory(p.dirname(libraryDb)),
    ]) {
      await dir.create(recursive: true);
    }
  }
}
