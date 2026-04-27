import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'package:tutor1on1/db/app_database.dart';

void main() {
  test('migrates from v1 to current schema', () async {
    final tempDir = await Directory.systemTemp.createTemp('tutor1on1');
    final dbFile = File(p.join(tempDir.path, 'test.db'));

    final rawDb = sqlite3.sqlite3.open(dbFile.path);
    rawDb.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL,
        pin_hash TEXT NOT NULL,
        role TEXT NOT NULL,
        teacher_id INTEGER,
        created_at TEXT NOT NULL
      );
    ''');
    rawDb.execute('''
      CREATE TABLE course_versions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        teacher_id INTEGER NOT NULL,
        subject TEXT NOT NULL,
        granularity INTEGER NOT NULL,
        textbook_text TEXT NOT NULL,
        tree_gen_status TEXT NOT NULL,
        tree_gen_raw_response TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT
      );
    ''');
    rawDb.execute('''
      CREATE TABLE course_nodes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        course_version_id INTEGER NOT NULL,
        kp_key TEXT NOT NULL,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        order_index INTEGER NOT NULL
      );
    ''');
    rawDb.execute('''
      CREATE TABLE course_edges (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        course_version_id INTEGER NOT NULL,
        from_kp_key TEXT NOT NULL,
        to_kp_key TEXT NOT NULL
      );
    ''');
    rawDb.execute('''
      CREATE TABLE student_course_assignments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id INTEGER NOT NULL,
        course_version_id INTEGER NOT NULL,
        assigned_at TEXT NOT NULL
      );
    ''');
    rawDb.execute('''
      CREATE TABLE progress_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id INTEGER NOT NULL,
        course_version_id INTEGER NOT NULL,
        kp_key TEXT NOT NULL,
        lit INTEGER NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    rawDb.execute('''
      CREATE TABLE chat_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id INTEGER NOT NULL,
        course_version_id INTEGER NOT NULL,
        kp_key TEXT NOT NULL,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        status TEXT NOT NULL,
        summary_text TEXT,
        summary_lit INTEGER,
        summary_raw_response TEXT,
        summarize_call_id INTEGER
      );
    ''');
    rawDb.execute('''
      CREATE TABLE chat_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        action TEXT,
        created_at TEXT NOT NULL
      );
    ''');
    rawDb.execute('''
      CREATE TABLE llm_calls (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        call_hash TEXT NOT NULL,
        prompt_name TEXT NOT NULL,
        rendered_prompt TEXT NOT NULL,
        model TEXT NOT NULL,
        base_url TEXT NOT NULL,
        response_text TEXT,
        response_json TEXT,
        parse_valid INTEGER,
        parse_error TEXT,
        latency_ms INTEGER,
        created_at TEXT NOT NULL,
        mode TEXT NOT NULL
      );
    ''');
    rawDb.execute('''
      CREATE TABLE app_settings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        base_url TEXT NOT NULL,
        model TEXT NOT NULL,
        timeout_seconds INTEGER NOT NULL,
        max_tokens INTEGER NOT NULL,
        llm_mode TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    rawDb.execute('PRAGMA user_version = 1;');
    rawDb.dispose();

    final db = AppDatabase.forTesting(NativeDatabase(dbFile));
    await db.customSelect('SELECT 1').get();

    final courseInfo =
        await db.customSelect('PRAGMA table_info(course_versions)').get();
    final courseColumns = courseInfo.map((row) => row.data['name']).toSet();
    expect(courseColumns.contains('tree_gen_valid'), isTrue);
    expect(courseColumns.contains('tree_gen_parse_error'), isTrue);
    expect(courseColumns.contains('source_path'), isTrue);

    final sessionInfo =
        await db.customSelect('PRAGMA table_info(chat_sessions)').get();
    final sessionColumns = sessionInfo.map((row) => row.data['name']).toSet();
    expect(sessionColumns.contains('summary_valid'), isTrue);
    expect(sessionColumns.contains('title'), isTrue);

    final progressInfo =
        await db.customSelect('PRAGMA table_info(progress_entries)').get();
    final progressColumns = progressInfo.map((row) => row.data['name']).toSet();
    expect(progressColumns.contains('question_level'), isTrue);
    expect(progressColumns.contains('summary_text'), isTrue);
    expect(progressColumns.contains('summary_raw_response'), isTrue);
    expect(progressColumns.contains('summary_valid'), isTrue);

    final llmInfo = await db.customSelect('PRAGMA table_info(llm_calls)').get();
    final llmColumns = llmInfo.map((row) => row.data['name']).toSet();
    expect(llmColumns.contains('teacher_id'), isTrue);
    expect(llmColumns.contains('student_id'), isTrue);
    expect(llmColumns.contains('course_version_id'), isTrue);
    expect(llmColumns.contains('session_id'), isTrue);
    expect(llmColumns.contains('kp_key'), isTrue);
    expect(llmColumns.contains('action'), isTrue);

    final settingsInfo =
        await db.customSelect('PRAGMA table_info(app_settings)').get();
    final settingsColumns = settingsInfo.map((row) => row.data['name']).toSet();
    expect(settingsColumns.contains('locale'), isTrue);
    expect(settingsColumns.contains('provider_id'), isTrue);
    expect(settingsColumns.contains('reasoning_effort'), isTrue);

    final apiConfigInfo =
        await db.customSelect('PRAGMA table_info(api_configs)').get();
    final apiConfigColumns =
        apiConfigInfo.map((row) => row.data['name']).toSet();
    expect(apiConfigColumns.contains('reasoning_effort'), isTrue);

    final apiConfigTable = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='api_configs'",
        )
        .get();
    expect(apiConfigTable.isNotEmpty, isTrue);

    final promptTable = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='prompt_templates'",
        )
        .get();
    expect(promptTable.isNotEmpty, isTrue);

    await db.close();
  });

  test('migration to v31 drops legacy prompt template overrides', () async {
    final tempDir = await Directory.systemTemp.createTemp('tutor1on1');
    final dbFile = File(p.join(tempDir.path, 'test.db'));

    final rawDb = sqlite3.sqlite3.open(dbFile.path);
    rawDb.execute('''
      CREATE TABLE prompt_templates (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        teacher_id INTEGER NOT NULL,
        course_key TEXT NULL,
        student_id INTEGER NULL,
        prompt_name TEXT NOT NULL,
        content TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 0 CHECK (is_active IN (0, 1)),
        created_at INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER))
      );
    ''');
    rawDb.execute('''
      INSERT INTO prompt_templates (
        teacher_id,
        course_key,
        student_id,
        prompt_name,
        content,
        is_active
      ) VALUES (1, 'course_math', 2, 'learn', 'legacy scoped prompt', 1);
    ''');
    rawDb.execute('PRAGMA user_version = 30;');
    rawDb.dispose();

    final db = AppDatabase.forTesting(NativeDatabase(dbFile));
    final rows = await db.customSelect('SELECT * FROM prompt_templates').get();

    expect(rows, isEmpty);

    await db.close();
  });

  test('migration to v32 deduplicates api configs with null audio models',
      () async {
    final tempDir = await Directory.systemTemp.createTemp('tutor1on1');
    final dbFile = File(p.join(tempDir.path, 'test.db'));

    final rawDb = sqlite3.sqlite3.open(dbFile.path);
    rawDb.execute('''
      CREATE TABLE api_configs (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        base_url TEXT NOT NULL,
        model TEXT NOT NULL,
        reasoning_effort TEXT NOT NULL DEFAULT 'medium',
        tts_model TEXT NULL,
        stt_model TEXT NULL,
        api_key_hash TEXT NOT NULL,
        created_at TEXT NOT NULL
      );
    ''');
    rawDb.execute('''
      INSERT INTO api_configs (
        base_url,
        model,
        reasoning_effort,
        tts_model,
        stt_model,
        api_key_hash,
        created_at
      ) VALUES
      (
        'https://API.openai.com/v1',
        'gpt-test',
        'HIGH',
        NULL,
        NULL,
        'hash_1',
        '2026-04-27T00:00:00.000'
      ),
      (
        'https://api.openai.com/v1',
        'gpt-test',
        'high',
        NULL,
        NULL,
        'hash_1',
        '2026-04-27T00:01:00.000'
      );
    ''');
    rawDb.execute('PRAGMA user_version = 31;');
    rawDb.dispose();

    final db = AppDatabase.forTesting(NativeDatabase(dbFile));
    await db.customSelect('SELECT 1').get();

    final rows =
        await db.customSelect('SELECT id FROM api_configs ORDER BY id').get();
    final indexes =
        await db.customSelect('PRAGMA index_list(api_configs)').get();
    final duplicate = await db.insertApiConfig(
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-test',
      reasoningEffort: 'high',
      ttsModel: '',
      sttModel: '',
      apiKeyHash: 'hash_1',
    );

    expect(rows, hasLength(1));
    expect(
      indexes.map((row) => row.data['name']),
      contains('uq_api_configs_normalized'),
    );
    expect(duplicate, isFalse);

    await db.close();
  });

  test('migration to v33 creates api model cache table', () async {
    final tempDir = await Directory.systemTemp.createTemp('tutor1on1');
    final dbFile = File(p.join(tempDir.path, 'test.db'));

    final rawDb = sqlite3.sqlite3.open(dbFile.path);
    rawDb.execute('PRAGMA user_version = 32;');
    rawDb.dispose();

    final db = AppDatabase.forTesting(NativeDatabase(dbFile));
    final rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'api_model_caches'",
        )
        .get();

    expect(rows, hasLength(1));

    await db.close();
  });
}
