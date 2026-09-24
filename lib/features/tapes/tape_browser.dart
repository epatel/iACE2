import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/db/app_database.dart';
import '../emulator/emulator_controller.dart';
import 'db_tape_library.dart';

/// Lists the saved tapes: load a dictionary into the ACE, export a tape as a
/// `.TAP` file, import `.TAP` files, delete.
class TapeBrowser extends StatefulWidget {
  const TapeBrowser({super.key, required this.tapes, this.onLoad});

  final DbTapeLibrary tapes;

  /// Called after a `LOAD` was typed, e.g. to show the screen.
  final VoidCallback? onLoad;

  static Future<void> show(
    BuildContext context, {
    required DbTapeLibrary tapes,
    VoidCallback? onLoad,
  }) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.7,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider.value(
            value: context.read<EmulatorController>(),
          ),
        ],
        child: TapeBrowser(tapes: tapes, onLoad: onLoad),
      ),
    ),
  );

  @override
  State<TapeBrowser> createState() => _TapeBrowserState();
}

class _TapeBrowserState extends State<TapeBrowser> {
  late Future<List<TapeRow>> _rows = widget.tapes.all();

  void _reload() {
    // A block body: setState must not be given a callback that returns a Future.
    setState(() {
      _rows = widget.tapes.all();
    });
  }

  void _message(String text) =>
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(text)));

  Future<void> _import() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Import a .TAP file',
      type: FileType.any,
    );
    if (file == null) return;
    try {
      final names = await widget.tapes.importTap(await file.readAsBytes());
      _message('Imported ${names.join(', ')}');
    } on FormatException catch (e) {
      _message('${file.name} is not a Jupiter ACE .TAP file (${e.message})');
    }
    _reload();
  }

  Future<void> _export(TapeRow row, Rect origin) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, '${row.name}.tap'));
    await file.writeAsBytes(row.data);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], sharePositionOrigin: origin),
    );
  }

  Future<void> _delete(TapeRow row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${row.name}?'),
        content: const Text('The tape is removed from this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.tapes.delete(row.id);
    _reload();
  }

  void _load(TapeRow row) {
    context.read<EmulatorController>().type('LOAD ${row.name}\n');
    Navigator.pop(context);
    widget.onLoad?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tapes'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton.icon(
            key: const ValueKey('import-tap'),
            onPressed: _import,
            icon: const Icon(Icons.file_open),
            label: const Text('Import .TAP'),
          ),
        ],
      ),
      body: FutureBuilder(
        future: _rows,
        builder: (context, snapshot) {
          final rows = snapshot.data;
          if (rows == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (rows.isEmpty) {
            return const Center(
              child: Text('No tapes yet. SAVE a dictionary on the ACE.'),
            );
          }
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final row = rows[i];
              final isDict = row.kind == 'dic';
              return ListTile(
                key: ValueKey('tape-${row.name}.${row.kind}'),
                leading: Icon(isDict ? Icons.menu_book : Icons.memory),
                title: Text(row.name),
                subtitle: Text(
                  '${isDict ? 'Dictionary' : 'Bytes'} · '
                  '${row.data.length} bytes · ${row.source}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isDict)
                      TextButton(
                        onPressed: () => _load(row),
                        child: const Text('LOAD'),
                      ),
                    Builder(
                      builder: (context) => IconButton(
                        tooltip: 'Export as .TAP',
                        icon: const Icon(Icons.ios_share),
                        onPressed: () {
                          final box = context.findRenderObject()! as RenderBox;
                          _export(
                            row,
                            box.localToGlobal(Offset.zero) & box.size,
                          );
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(row),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
