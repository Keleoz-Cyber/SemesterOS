import 'dart:io';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

abstract interface class CalendarStore {
  Future<Map<String, dynamic>?> read(String owner);
  Future<void> write(String owner, Map<String, dynamic> value);
  Future<void> clear(String owner);
  Future<void> close();
}

class CalendarCache extends GeneratedDatabase implements CalendarStore {
  CalendarCache()
    : super(
        LazyDatabase(() async {
          final directory = await getApplicationSupportDirectory();
          return NativeDatabase.createInBackground(
            File('${directory.path}/calendar.sqlite'),
          );
        }),
      );
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement(
        'CREATE TABLE calendar_cache (owner TEXT PRIMARY KEY, payload TEXT NOT NULL)',
      );
    },
  );

  @override
  Future<Map<String, dynamic>?> read(String owner) async {
    final row = await customSelect(
      'SELECT payload FROM calendar_cache WHERE owner = ?',
      variables: [Variable(owner)],
    ).getSingleOrNull();
    return row == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(row.read<String>('payload')));
  }

  @override
  Future<void> write(
    String owner,
    Map<String, dynamic> value,
  ) => customStatement(
    'INSERT INTO calendar_cache(owner,payload) VALUES(?,?) ON CONFLICT(owner) DO UPDATE SET payload=excluded.payload',
    [owner, jsonEncode(value)],
  );

  @override
  Future<void> clear(String owner) =>
      customStatement('DELETE FROM calendar_cache WHERE owner = ?', [owner]);
}
