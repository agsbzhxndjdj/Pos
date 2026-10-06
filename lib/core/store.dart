import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/* ==========================================================
   6) دالة التخزين المحلي Offline-First (Doc + Store)
   ========================================================== */
/* ==========================================================
   6) دالة التخزين المحلي Offline-First (Store) — مصححة
   ========================================================== */
class Store {
  static Database? _db;



  static Future<void> init() async {
    await db;
  }



  static Future<Database> get db async => _db ??= await openDatabase(
        join(await getDatabasesPath(), 'pos.db'), version: 1,
        onCreate: (d, v) async {
          await d.execute('CREATE TABLE docs(table TEXT, id TEXT, data TEXT, updatedAt INTEGER, deleted INTEGER DEFAULT 0, PRIMARY KEY(table,id))');
          await d.execute('CREATE TABLE meta(k TEXT PRIMARY KEY, v TEXT)');
        });



  static Future<void> upsert(String table, String id, Map<String, dynamic> data, {bool deleted = false}) async {
    final d = await db;
    await d.insert('docs', {'table': table, 'id': id, 'data': jsonEncode(data),
        'updatedAt': DateTime.now().millisecondsSinceEpoch, 'deleted': deleted ? 1 : 0},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }



  static Future<List<Doc>> list(String table, {bool includeDeleted = false}) async {
    final d = await db;
    final rows = await d.query('docs', where: 'table = ?' + (includeDeleted ? '' : ' AND deleted = 0'), whereArgs: [table]);
    return rows.map((r) => Doc(table: table, id: r['id'] as String, data: jsonDecode(r['data'] as String) as Map<String, dynamic>,
        updatedAt: r['updatedAt'] as int, deleted: (r['deleted'] as int) == 1)).toList();
  }



  static Future<Doc?> get(String table, String id) async =>
      (await list(table, includeDeleted: true)).where((e) => e.id == id).firstOrNull;



  static Future<void> remove(String table, String id) async {
    final cur = await get(table, id);
    if (cur != null) await upsert(table, id, cur.data, deleted: true);
  }



  static Future<List<Doc>> changesSince(int ts) async {
    final d = await db;
    final rows = await d.query('docs', where: 'updatedAt > ?', whereArgs: [ts]);
    return rows.map((r) => Doc(table: r['table'] as String, id: r['id'] as String,
        data: jsonDecode(r['data'] as String) as Map<String, dynamic>,
        updatedAt: r['updatedAt'] as int, deleted: (r['deleted'] as int) == 1)).toList();
  }



  static Future<void> applyRemote(List<Doc> docs) async {
    for (final r in docs) {
      final local = await get(r.table, r.id);
      if (local == null || r.updatedAt > local.updatedAt) await upsert(r.table, r.id, r.data, deleted: r.deleted);
    }
  }



  static Future<String?> metaGet(String k) async =>
      (await (await db).query('meta', where: 'k = ?', whereArgs: [k])).firstOrNull?['v'] as String?;



  static Future<void> metaSet(String k, String v) async =>
      (await db).insert('meta', {'k': k, 'v': v}, conflictAlgorithm: ConflictAlgorithm.replace);
}
