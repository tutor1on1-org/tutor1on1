// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $UsersTable extends Users with TableInfo<$UsersTable, User> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UsersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _usernameMeta =
      const VerificationMeta('username');
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
      'username', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _pinHashMeta =
      const VerificationMeta('pinHash');
  @override
  late final GeneratedColumn<String> pinHash = GeneratedColumn<String>(
      'pin_hash', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
      'role', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _teacherIdMeta =
      const VerificationMeta('teacherId');
  @override
  late final GeneratedColumn<int> teacherId = GeneratedColumn<int>(
      'teacher_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _remoteUserIdMeta =
      const VerificationMeta('remoteUserId');
  @override
  late final GeneratedColumn<int> remoteUserId = GeneratedColumn<int>(
      'remote_user_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns =>
      [id, username, pinHash, role, teacherId, remoteUserId, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'users';
  @override
  VerificationContext validateIntegrity(Insertable<User> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('username')) {
      context.handle(_usernameMeta,
          username.isAcceptableOrUnknown(data['username']!, _usernameMeta));
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('pin_hash')) {
      context.handle(_pinHashMeta,
          pinHash.isAcceptableOrUnknown(data['pin_hash']!, _pinHashMeta));
    } else if (isInserting) {
      context.missing(_pinHashMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
          _roleMeta, role.isAcceptableOrUnknown(data['role']!, _roleMeta));
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('teacher_id')) {
      context.handle(_teacherIdMeta,
          teacherId.isAcceptableOrUnknown(data['teacher_id']!, _teacherIdMeta));
    }
    if (data.containsKey('remote_user_id')) {
      context.handle(
          _remoteUserIdMeta,
          remoteUserId.isAcceptableOrUnknown(
              data['remote_user_id']!, _remoteUserIdMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
        {username},
      ];
  @override
  User map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return User(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      username: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}username'])!,
      pinHash: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}pin_hash'])!,
      role: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}role'])!,
      teacherId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}teacher_id']),
      remoteUserId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}remote_user_id']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $UsersTable createAlias(String alias) {
    return $UsersTable(attachedDatabase, alias);
  }
}

class User extends DataClass implements Insertable<User> {
  final int id;
  final String username;
  final String pinHash;
  final String role;
  final int? teacherId;
  final int? remoteUserId;
  final DateTime createdAt;
  const User(
      {required this.id,
      required this.username,
      required this.pinHash,
      required this.role,
      this.teacherId,
      this.remoteUserId,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['username'] = Variable<String>(username);
    map['pin_hash'] = Variable<String>(pinHash);
    map['role'] = Variable<String>(role);
    if (!nullToAbsent || teacherId != null) {
      map['teacher_id'] = Variable<int>(teacherId);
    }
    if (!nullToAbsent || remoteUserId != null) {
      map['remote_user_id'] = Variable<int>(remoteUserId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  UsersCompanion toCompanion(bool nullToAbsent) {
    return UsersCompanion(
      id: Value(id),
      username: Value(username),
      pinHash: Value(pinHash),
      role: Value(role),
      teacherId: teacherId == null && nullToAbsent
          ? const Value.absent()
          : Value(teacherId),
      remoteUserId: remoteUserId == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteUserId),
      createdAt: Value(createdAt),
    );
  }

  factory User.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return User(
      id: serializer.fromJson<int>(json['id']),
      username: serializer.fromJson<String>(json['username']),
      pinHash: serializer.fromJson<String>(json['pinHash']),
      role: serializer.fromJson<String>(json['role']),
      teacherId: serializer.fromJson<int?>(json['teacherId']),
      remoteUserId: serializer.fromJson<int?>(json['remoteUserId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'username': serializer.toJson<String>(username),
      'pinHash': serializer.toJson<String>(pinHash),
      'role': serializer.toJson<String>(role),
      'teacherId': serializer.toJson<int?>(teacherId),
      'remoteUserId': serializer.toJson<int?>(remoteUserId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  User copyWith(
          {int? id,
          String? username,
          String? pinHash,
          String? role,
          Value<int?> teacherId = const Value.absent(),
          Value<int?> remoteUserId = const Value.absent(),
          DateTime? createdAt}) =>
      User(
        id: id ?? this.id,
        username: username ?? this.username,
        pinHash: pinHash ?? this.pinHash,
        role: role ?? this.role,
        teacherId: teacherId.present ? teacherId.value : this.teacherId,
        remoteUserId:
            remoteUserId.present ? remoteUserId.value : this.remoteUserId,
        createdAt: createdAt ?? this.createdAt,
      );
  User copyWithCompanion(UsersCompanion data) {
    return User(
      id: data.id.present ? data.id.value : this.id,
      username: data.username.present ? data.username.value : this.username,
      pinHash: data.pinHash.present ? data.pinHash.value : this.pinHash,
      role: data.role.present ? data.role.value : this.role,
      teacherId: data.teacherId.present ? data.teacherId.value : this.teacherId,
      remoteUserId: data.remoteUserId.present
          ? data.remoteUserId.value
          : this.remoteUserId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('User(')
          ..write('id: $id, ')
          ..write('username: $username, ')
          ..write('pinHash: $pinHash, ')
          ..write('role: $role, ')
          ..write('teacherId: $teacherId, ')
          ..write('remoteUserId: $remoteUserId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, username, pinHash, role, teacherId, remoteUserId, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is User &&
          other.id == this.id &&
          other.username == this.username &&
          other.pinHash == this.pinHash &&
          other.role == this.role &&
          other.teacherId == this.teacherId &&
          other.remoteUserId == this.remoteUserId &&
          other.createdAt == this.createdAt);
}

class UsersCompanion extends UpdateCompanion<User> {
  final Value<int> id;
  final Value<String> username;
  final Value<String> pinHash;
  final Value<String> role;
  final Value<int?> teacherId;
  final Value<int?> remoteUserId;
  final Value<DateTime> createdAt;
  const UsersCompanion({
    this.id = const Value.absent(),
    this.username = const Value.absent(),
    this.pinHash = const Value.absent(),
    this.role = const Value.absent(),
    this.teacherId = const Value.absent(),
    this.remoteUserId = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  UsersCompanion.insert({
    this.id = const Value.absent(),
    required String username,
    required String pinHash,
    required String role,
    this.teacherId = const Value.absent(),
    this.remoteUserId = const Value.absent(),
    this.createdAt = const Value.absent(),
  })  : username = Value(username),
        pinHash = Value(pinHash),
        role = Value(role);
  static Insertable<User> custom({
    Expression<int>? id,
    Expression<String>? username,
    Expression<String>? pinHash,
    Expression<String>? role,
    Expression<int>? teacherId,
    Expression<int>? remoteUserId,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (username != null) 'username': username,
      if (pinHash != null) 'pin_hash': pinHash,
      if (role != null) 'role': role,
      if (teacherId != null) 'teacher_id': teacherId,
      if (remoteUserId != null) 'remote_user_id': remoteUserId,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  UsersCompanion copyWith(
      {Value<int>? id,
      Value<String>? username,
      Value<String>? pinHash,
      Value<String>? role,
      Value<int?>? teacherId,
      Value<int?>? remoteUserId,
      Value<DateTime>? createdAt}) {
    return UsersCompanion(
      id: id ?? this.id,
      username: username ?? this.username,
      pinHash: pinHash ?? this.pinHash,
      role: role ?? this.role,
      teacherId: teacherId ?? this.teacherId,
      remoteUserId: remoteUserId ?? this.remoteUserId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (pinHash.present) {
      map['pin_hash'] = Variable<String>(pinHash.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (teacherId.present) {
      map['teacher_id'] = Variable<int>(teacherId.value);
    }
    if (remoteUserId.present) {
      map['remote_user_id'] = Variable<int>(remoteUserId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UsersCompanion(')
          ..write('id: $id, ')
          ..write('username: $username, ')
          ..write('pinHash: $pinHash, ')
          ..write('role: $role, ')
          ..write('teacherId: $teacherId, ')
          ..write('remoteUserId: $remoteUserId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $CourseVersionsTable extends CourseVersions
    with TableInfo<$CourseVersionsTable, CourseVersion> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CourseVersionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _teacherIdMeta =
      const VerificationMeta('teacherId');
  @override
  late final GeneratedColumn<int> teacherId = GeneratedColumn<int>(
      'teacher_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _subjectMeta =
      const VerificationMeta('subject');
  @override
  late final GeneratedColumn<String> subject = GeneratedColumn<String>(
      'subject', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sourcePathMeta =
      const VerificationMeta('sourcePath');
  @override
  late final GeneratedColumn<String> sourcePath = GeneratedColumn<String>(
      'source_path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _granularityMeta =
      const VerificationMeta('granularity');
  @override
  late final GeneratedColumn<int> granularity = GeneratedColumn<int>(
      'granularity', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _textbookTextMeta =
      const VerificationMeta('textbookText');
  @override
  late final GeneratedColumn<String> textbookText = GeneratedColumn<String>(
      'textbook_text', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _treeGenStatusMeta =
      const VerificationMeta('treeGenStatus');
  @override
  late final GeneratedColumn<String> treeGenStatus = GeneratedColumn<String>(
      'tree_gen_status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('pending'));
  static const VerificationMeta _treeGenRawResponseMeta =
      const VerificationMeta('treeGenRawResponse');
  @override
  late final GeneratedColumn<String> treeGenRawResponse =
      GeneratedColumn<String>('tree_gen_raw_response', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _treeGenValidMeta =
      const VerificationMeta('treeGenValid');
  @override
  late final GeneratedColumn<bool> treeGenValid = GeneratedColumn<bool>(
      'tree_gen_valid', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("tree_gen_valid" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _treeGenParseErrorMeta =
      const VerificationMeta('treeGenParseError');
  @override
  late final GeneratedColumn<String> treeGenParseError =
      GeneratedColumn<String>('tree_gen_parse_error', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        teacherId,
        subject,
        sourcePath,
        granularity,
        textbookText,
        treeGenStatus,
        treeGenRawResponse,
        treeGenValid,
        treeGenParseError,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'course_versions';
  @override
  VerificationContext validateIntegrity(Insertable<CourseVersion> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('teacher_id')) {
      context.handle(_teacherIdMeta,
          teacherId.isAcceptableOrUnknown(data['teacher_id']!, _teacherIdMeta));
    } else if (isInserting) {
      context.missing(_teacherIdMeta);
    }
    if (data.containsKey('subject')) {
      context.handle(_subjectMeta,
          subject.isAcceptableOrUnknown(data['subject']!, _subjectMeta));
    } else if (isInserting) {
      context.missing(_subjectMeta);
    }
    if (data.containsKey('source_path')) {
      context.handle(
          _sourcePathMeta,
          sourcePath.isAcceptableOrUnknown(
              data['source_path']!, _sourcePathMeta));
    }
    if (data.containsKey('granularity')) {
      context.handle(
          _granularityMeta,
          granularity.isAcceptableOrUnknown(
              data['granularity']!, _granularityMeta));
    } else if (isInserting) {
      context.missing(_granularityMeta);
    }
    if (data.containsKey('textbook_text')) {
      context.handle(
          _textbookTextMeta,
          textbookText.isAcceptableOrUnknown(
              data['textbook_text']!, _textbookTextMeta));
    } else if (isInserting) {
      context.missing(_textbookTextMeta);
    }
    if (data.containsKey('tree_gen_status')) {
      context.handle(
          _treeGenStatusMeta,
          treeGenStatus.isAcceptableOrUnknown(
              data['tree_gen_status']!, _treeGenStatusMeta));
    }
    if (data.containsKey('tree_gen_raw_response')) {
      context.handle(
          _treeGenRawResponseMeta,
          treeGenRawResponse.isAcceptableOrUnknown(
              data['tree_gen_raw_response']!, _treeGenRawResponseMeta));
    }
    if (data.containsKey('tree_gen_valid')) {
      context.handle(
          _treeGenValidMeta,
          treeGenValid.isAcceptableOrUnknown(
              data['tree_gen_valid']!, _treeGenValidMeta));
    }
    if (data.containsKey('tree_gen_parse_error')) {
      context.handle(
          _treeGenParseErrorMeta,
          treeGenParseError.isAcceptableOrUnknown(
              data['tree_gen_parse_error']!, _treeGenParseErrorMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CourseVersion map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CourseVersion(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      teacherId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}teacher_id'])!,
      subject: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}subject'])!,
      sourcePath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source_path']),
      granularity: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}granularity'])!,
      textbookText: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}textbook_text'])!,
      treeGenStatus: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}tree_gen_status'])!,
      treeGenRawResponse: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}tree_gen_raw_response']),
      treeGenValid: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}tree_gen_valid'])!,
      treeGenParseError: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}tree_gen_parse_error']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at']),
    );
  }

  @override
  $CourseVersionsTable createAlias(String alias) {
    return $CourseVersionsTable(attachedDatabase, alias);
  }
}

class CourseVersion extends DataClass implements Insertable<CourseVersion> {
  final int id;
  final int teacherId;
  final String subject;
  final String? sourcePath;
  final int granularity;
  final String textbookText;
  final String treeGenStatus;
  final String? treeGenRawResponse;
  final bool treeGenValid;
  final String? treeGenParseError;
  final DateTime createdAt;
  final DateTime? updatedAt;
  const CourseVersion(
      {required this.id,
      required this.teacherId,
      required this.subject,
      this.sourcePath,
      required this.granularity,
      required this.textbookText,
      required this.treeGenStatus,
      this.treeGenRawResponse,
      required this.treeGenValid,
      this.treeGenParseError,
      required this.createdAt,
      this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['teacher_id'] = Variable<int>(teacherId);
    map['subject'] = Variable<String>(subject);
    if (!nullToAbsent || sourcePath != null) {
      map['source_path'] = Variable<String>(sourcePath);
    }
    map['granularity'] = Variable<int>(granularity);
    map['textbook_text'] = Variable<String>(textbookText);
    map['tree_gen_status'] = Variable<String>(treeGenStatus);
    if (!nullToAbsent || treeGenRawResponse != null) {
      map['tree_gen_raw_response'] = Variable<String>(treeGenRawResponse);
    }
    map['tree_gen_valid'] = Variable<bool>(treeGenValid);
    if (!nullToAbsent || treeGenParseError != null) {
      map['tree_gen_parse_error'] = Variable<String>(treeGenParseError);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    return map;
  }

  CourseVersionsCompanion toCompanion(bool nullToAbsent) {
    return CourseVersionsCompanion(
      id: Value(id),
      teacherId: Value(teacherId),
      subject: Value(subject),
      sourcePath: sourcePath == null && nullToAbsent
          ? const Value.absent()
          : Value(sourcePath),
      granularity: Value(granularity),
      textbookText: Value(textbookText),
      treeGenStatus: Value(treeGenStatus),
      treeGenRawResponse: treeGenRawResponse == null && nullToAbsent
          ? const Value.absent()
          : Value(treeGenRawResponse),
      treeGenValid: Value(treeGenValid),
      treeGenParseError: treeGenParseError == null && nullToAbsent
          ? const Value.absent()
          : Value(treeGenParseError),
      createdAt: Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory CourseVersion.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CourseVersion(
      id: serializer.fromJson<int>(json['id']),
      teacherId: serializer.fromJson<int>(json['teacherId']),
      subject: serializer.fromJson<String>(json['subject']),
      sourcePath: serializer.fromJson<String?>(json['sourcePath']),
      granularity: serializer.fromJson<int>(json['granularity']),
      textbookText: serializer.fromJson<String>(json['textbookText']),
      treeGenStatus: serializer.fromJson<String>(json['treeGenStatus']),
      treeGenRawResponse:
          serializer.fromJson<String?>(json['treeGenRawResponse']),
      treeGenValid: serializer.fromJson<bool>(json['treeGenValid']),
      treeGenParseError:
          serializer.fromJson<String?>(json['treeGenParseError']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'teacherId': serializer.toJson<int>(teacherId),
      'subject': serializer.toJson<String>(subject),
      'sourcePath': serializer.toJson<String?>(sourcePath),
      'granularity': serializer.toJson<int>(granularity),
      'textbookText': serializer.toJson<String>(textbookText),
      'treeGenStatus': serializer.toJson<String>(treeGenStatus),
      'treeGenRawResponse': serializer.toJson<String?>(treeGenRawResponse),
      'treeGenValid': serializer.toJson<bool>(treeGenValid),
      'treeGenParseError': serializer.toJson<String?>(treeGenParseError),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
    };
  }

  CourseVersion copyWith(
          {int? id,
          int? teacherId,
          String? subject,
          Value<String?> sourcePath = const Value.absent(),
          int? granularity,
          String? textbookText,
          String? treeGenStatus,
          Value<String?> treeGenRawResponse = const Value.absent(),
          bool? treeGenValid,
          Value<String?> treeGenParseError = const Value.absent(),
          DateTime? createdAt,
          Value<DateTime?> updatedAt = const Value.absent()}) =>
      CourseVersion(
        id: id ?? this.id,
        teacherId: teacherId ?? this.teacherId,
        subject: subject ?? this.subject,
        sourcePath: sourcePath.present ? sourcePath.value : this.sourcePath,
        granularity: granularity ?? this.granularity,
        textbookText: textbookText ?? this.textbookText,
        treeGenStatus: treeGenStatus ?? this.treeGenStatus,
        treeGenRawResponse: treeGenRawResponse.present
            ? treeGenRawResponse.value
            : this.treeGenRawResponse,
        treeGenValid: treeGenValid ?? this.treeGenValid,
        treeGenParseError: treeGenParseError.present
            ? treeGenParseError.value
            : this.treeGenParseError,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
      );
  CourseVersion copyWithCompanion(CourseVersionsCompanion data) {
    return CourseVersion(
      id: data.id.present ? data.id.value : this.id,
      teacherId: data.teacherId.present ? data.teacherId.value : this.teacherId,
      subject: data.subject.present ? data.subject.value : this.subject,
      sourcePath:
          data.sourcePath.present ? data.sourcePath.value : this.sourcePath,
      granularity:
          data.granularity.present ? data.granularity.value : this.granularity,
      textbookText: data.textbookText.present
          ? data.textbookText.value
          : this.textbookText,
      treeGenStatus: data.treeGenStatus.present
          ? data.treeGenStatus.value
          : this.treeGenStatus,
      treeGenRawResponse: data.treeGenRawResponse.present
          ? data.treeGenRawResponse.value
          : this.treeGenRawResponse,
      treeGenValid: data.treeGenValid.present
          ? data.treeGenValid.value
          : this.treeGenValid,
      treeGenParseError: data.treeGenParseError.present
          ? data.treeGenParseError.value
          : this.treeGenParseError,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CourseVersion(')
          ..write('id: $id, ')
          ..write('teacherId: $teacherId, ')
          ..write('subject: $subject, ')
          ..write('sourcePath: $sourcePath, ')
          ..write('granularity: $granularity, ')
          ..write('textbookText: $textbookText, ')
          ..write('treeGenStatus: $treeGenStatus, ')
          ..write('treeGenRawResponse: $treeGenRawResponse, ')
          ..write('treeGenValid: $treeGenValid, ')
          ..write('treeGenParseError: $treeGenParseError, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      teacherId,
      subject,
      sourcePath,
      granularity,
      textbookText,
      treeGenStatus,
      treeGenRawResponse,
      treeGenValid,
      treeGenParseError,
      createdAt,
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CourseVersion &&
          other.id == this.id &&
          other.teacherId == this.teacherId &&
          other.subject == this.subject &&
          other.sourcePath == this.sourcePath &&
          other.granularity == this.granularity &&
          other.textbookText == this.textbookText &&
          other.treeGenStatus == this.treeGenStatus &&
          other.treeGenRawResponse == this.treeGenRawResponse &&
          other.treeGenValid == this.treeGenValid &&
          other.treeGenParseError == this.treeGenParseError &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CourseVersionsCompanion extends UpdateCompanion<CourseVersion> {
  final Value<int> id;
  final Value<int> teacherId;
  final Value<String> subject;
  final Value<String?> sourcePath;
  final Value<int> granularity;
  final Value<String> textbookText;
  final Value<String> treeGenStatus;
  final Value<String?> treeGenRawResponse;
  final Value<bool> treeGenValid;
  final Value<String?> treeGenParseError;
  final Value<DateTime> createdAt;
  final Value<DateTime?> updatedAt;
  const CourseVersionsCompanion({
    this.id = const Value.absent(),
    this.teacherId = const Value.absent(),
    this.subject = const Value.absent(),
    this.sourcePath = const Value.absent(),
    this.granularity = const Value.absent(),
    this.textbookText = const Value.absent(),
    this.treeGenStatus = const Value.absent(),
    this.treeGenRawResponse = const Value.absent(),
    this.treeGenValid = const Value.absent(),
    this.treeGenParseError = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  CourseVersionsCompanion.insert({
    this.id = const Value.absent(),
    required int teacherId,
    required String subject,
    this.sourcePath = const Value.absent(),
    required int granularity,
    required String textbookText,
    this.treeGenStatus = const Value.absent(),
    this.treeGenRawResponse = const Value.absent(),
    this.treeGenValid = const Value.absent(),
    this.treeGenParseError = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  })  : teacherId = Value(teacherId),
        subject = Value(subject),
        granularity = Value(granularity),
        textbookText = Value(textbookText);
  static Insertable<CourseVersion> custom({
    Expression<int>? id,
    Expression<int>? teacherId,
    Expression<String>? subject,
    Expression<String>? sourcePath,
    Expression<int>? granularity,
    Expression<String>? textbookText,
    Expression<String>? treeGenStatus,
    Expression<String>? treeGenRawResponse,
    Expression<bool>? treeGenValid,
    Expression<String>? treeGenParseError,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (teacherId != null) 'teacher_id': teacherId,
      if (subject != null) 'subject': subject,
      if (sourcePath != null) 'source_path': sourcePath,
      if (granularity != null) 'granularity': granularity,
      if (textbookText != null) 'textbook_text': textbookText,
      if (treeGenStatus != null) 'tree_gen_status': treeGenStatus,
      if (treeGenRawResponse != null)
        'tree_gen_raw_response': treeGenRawResponse,
      if (treeGenValid != null) 'tree_gen_valid': treeGenValid,
      if (treeGenParseError != null) 'tree_gen_parse_error': treeGenParseError,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  CourseVersionsCompanion copyWith(
      {Value<int>? id,
      Value<int>? teacherId,
      Value<String>? subject,
      Value<String?>? sourcePath,
      Value<int>? granularity,
      Value<String>? textbookText,
      Value<String>? treeGenStatus,
      Value<String?>? treeGenRawResponse,
      Value<bool>? treeGenValid,
      Value<String?>? treeGenParseError,
      Value<DateTime>? createdAt,
      Value<DateTime?>? updatedAt}) {
    return CourseVersionsCompanion(
      id: id ?? this.id,
      teacherId: teacherId ?? this.teacherId,
      subject: subject ?? this.subject,
      sourcePath: sourcePath ?? this.sourcePath,
      granularity: granularity ?? this.granularity,
      textbookText: textbookText ?? this.textbookText,
      treeGenStatus: treeGenStatus ?? this.treeGenStatus,
      treeGenRawResponse: treeGenRawResponse ?? this.treeGenRawResponse,
      treeGenValid: treeGenValid ?? this.treeGenValid,
      treeGenParseError: treeGenParseError ?? this.treeGenParseError,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (teacherId.present) {
      map['teacher_id'] = Variable<int>(teacherId.value);
    }
    if (subject.present) {
      map['subject'] = Variable<String>(subject.value);
    }
    if (sourcePath.present) {
      map['source_path'] = Variable<String>(sourcePath.value);
    }
    if (granularity.present) {
      map['granularity'] = Variable<int>(granularity.value);
    }
    if (textbookText.present) {
      map['textbook_text'] = Variable<String>(textbookText.value);
    }
    if (treeGenStatus.present) {
      map['tree_gen_status'] = Variable<String>(treeGenStatus.value);
    }
    if (treeGenRawResponse.present) {
      map['tree_gen_raw_response'] = Variable<String>(treeGenRawResponse.value);
    }
    if (treeGenValid.present) {
      map['tree_gen_valid'] = Variable<bool>(treeGenValid.value);
    }
    if (treeGenParseError.present) {
      map['tree_gen_parse_error'] = Variable<String>(treeGenParseError.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CourseVersionsCompanion(')
          ..write('id: $id, ')
          ..write('teacherId: $teacherId, ')
          ..write('subject: $subject, ')
          ..write('sourcePath: $sourcePath, ')
          ..write('granularity: $granularity, ')
          ..write('textbookText: $textbookText, ')
          ..write('treeGenStatus: $treeGenStatus, ')
          ..write('treeGenRawResponse: $treeGenRawResponse, ')
          ..write('treeGenValid: $treeGenValid, ')
          ..write('treeGenParseError: $treeGenParseError, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $CourseNodesTable extends CourseNodes
    with TableInfo<$CourseNodesTable, CourseNode> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CourseNodesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _courseVersionIdMeta =
      const VerificationMeta('courseVersionId');
  @override
  late final GeneratedColumn<int> courseVersionId = GeneratedColumn<int>(
      'course_version_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _kpKeyMeta = const VerificationMeta('kpKey');
  @override
  late final GeneratedColumn<String> kpKey = GeneratedColumn<String>(
      'kp_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _orderIndexMeta =
      const VerificationMeta('orderIndex');
  @override
  late final GeneratedColumn<int> orderIndex = GeneratedColumn<int>(
      'order_index', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, courseVersionId, kpKey, title, description, orderIndex];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'course_nodes';
  @override
  VerificationContext validateIntegrity(Insertable<CourseNode> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('course_version_id')) {
      context.handle(
          _courseVersionIdMeta,
          courseVersionId.isAcceptableOrUnknown(
              data['course_version_id']!, _courseVersionIdMeta));
    } else if (isInserting) {
      context.missing(_courseVersionIdMeta);
    }
    if (data.containsKey('kp_key')) {
      context.handle(
          _kpKeyMeta, kpKey.isAcceptableOrUnknown(data['kp_key']!, _kpKeyMeta));
    } else if (isInserting) {
      context.missing(_kpKeyMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('order_index')) {
      context.handle(
          _orderIndexMeta,
          orderIndex.isAcceptableOrUnknown(
              data['order_index']!, _orderIndexMeta));
    } else if (isInserting) {
      context.missing(_orderIndexMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
        {courseVersionId, kpKey},
      ];
  @override
  CourseNode map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CourseNode(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      courseVersionId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}course_version_id'])!,
      kpKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}kp_key'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description'])!,
      orderIndex: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}order_index'])!,
    );
  }

  @override
  $CourseNodesTable createAlias(String alias) {
    return $CourseNodesTable(attachedDatabase, alias);
  }
}

class CourseNode extends DataClass implements Insertable<CourseNode> {
  final int id;
  final int courseVersionId;
  final String kpKey;
  final String title;
  final String description;
  final int orderIndex;
  const CourseNode(
      {required this.id,
      required this.courseVersionId,
      required this.kpKey,
      required this.title,
      required this.description,
      required this.orderIndex});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['course_version_id'] = Variable<int>(courseVersionId);
    map['kp_key'] = Variable<String>(kpKey);
    map['title'] = Variable<String>(title);
    map['description'] = Variable<String>(description);
    map['order_index'] = Variable<int>(orderIndex);
    return map;
  }

  CourseNodesCompanion toCompanion(bool nullToAbsent) {
    return CourseNodesCompanion(
      id: Value(id),
      courseVersionId: Value(courseVersionId),
      kpKey: Value(kpKey),
      title: Value(title),
      description: Value(description),
      orderIndex: Value(orderIndex),
    );
  }

  factory CourseNode.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CourseNode(
      id: serializer.fromJson<int>(json['id']),
      courseVersionId: serializer.fromJson<int>(json['courseVersionId']),
      kpKey: serializer.fromJson<String>(json['kpKey']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String>(json['description']),
      orderIndex: serializer.fromJson<int>(json['orderIndex']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'courseVersionId': serializer.toJson<int>(courseVersionId),
      'kpKey': serializer.toJson<String>(kpKey),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String>(description),
      'orderIndex': serializer.toJson<int>(orderIndex),
    };
  }

  CourseNode copyWith(
          {int? id,
          int? courseVersionId,
          String? kpKey,
          String? title,
          String? description,
          int? orderIndex}) =>
      CourseNode(
        id: id ?? this.id,
        courseVersionId: courseVersionId ?? this.courseVersionId,
        kpKey: kpKey ?? this.kpKey,
        title: title ?? this.title,
        description: description ?? this.description,
        orderIndex: orderIndex ?? this.orderIndex,
      );
  CourseNode copyWithCompanion(CourseNodesCompanion data) {
    return CourseNode(
      id: data.id.present ? data.id.value : this.id,
      courseVersionId: data.courseVersionId.present
          ? data.courseVersionId.value
          : this.courseVersionId,
      kpKey: data.kpKey.present ? data.kpKey.value : this.kpKey,
      title: data.title.present ? data.title.value : this.title,
      description:
          data.description.present ? data.description.value : this.description,
      orderIndex:
          data.orderIndex.present ? data.orderIndex.value : this.orderIndex,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CourseNode(')
          ..write('id: $id, ')
          ..write('courseVersionId: $courseVersionId, ')
          ..write('kpKey: $kpKey, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('orderIndex: $orderIndex')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, courseVersionId, kpKey, title, description, orderIndex);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CourseNode &&
          other.id == this.id &&
          other.courseVersionId == this.courseVersionId &&
          other.kpKey == this.kpKey &&
          other.title == this.title &&
          other.description == this.description &&
          other.orderIndex == this.orderIndex);
}

class CourseNodesCompanion extends UpdateCompanion<CourseNode> {
  final Value<int> id;
  final Value<int> courseVersionId;
  final Value<String> kpKey;
  final Value<String> title;
  final Value<String> description;
  final Value<int> orderIndex;
  const CourseNodesCompanion({
    this.id = const Value.absent(),
    this.courseVersionId = const Value.absent(),
    this.kpKey = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.orderIndex = const Value.absent(),
  });
  CourseNodesCompanion.insert({
    this.id = const Value.absent(),
    required int courseVersionId,
    required String kpKey,
    required String title,
    required String description,
    required int orderIndex,
  })  : courseVersionId = Value(courseVersionId),
        kpKey = Value(kpKey),
        title = Value(title),
        description = Value(description),
        orderIndex = Value(orderIndex);
  static Insertable<CourseNode> custom({
    Expression<int>? id,
    Expression<int>? courseVersionId,
    Expression<String>? kpKey,
    Expression<String>? title,
    Expression<String>? description,
    Expression<int>? orderIndex,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (courseVersionId != null) 'course_version_id': courseVersionId,
      if (kpKey != null) 'kp_key': kpKey,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (orderIndex != null) 'order_index': orderIndex,
    });
  }

  CourseNodesCompanion copyWith(
      {Value<int>? id,
      Value<int>? courseVersionId,
      Value<String>? kpKey,
      Value<String>? title,
      Value<String>? description,
      Value<int>? orderIndex}) {
    return CourseNodesCompanion(
      id: id ?? this.id,
      courseVersionId: courseVersionId ?? this.courseVersionId,
      kpKey: kpKey ?? this.kpKey,
      title: title ?? this.title,
      description: description ?? this.description,
      orderIndex: orderIndex ?? this.orderIndex,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (courseVersionId.present) {
      map['course_version_id'] = Variable<int>(courseVersionId.value);
    }
    if (kpKey.present) {
      map['kp_key'] = Variable<String>(kpKey.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (orderIndex.present) {
      map['order_index'] = Variable<int>(orderIndex.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CourseNodesCompanion(')
          ..write('id: $id, ')
          ..write('courseVersionId: $courseVersionId, ')
          ..write('kpKey: $kpKey, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('orderIndex: $orderIndex')
          ..write(')'))
        .toString();
  }
}

class $CourseEdgesTable extends CourseEdges
    with TableInfo<$CourseEdgesTable, CourseEdge> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CourseEdgesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _courseVersionIdMeta =
      const VerificationMeta('courseVersionId');
  @override
  late final GeneratedColumn<int> courseVersionId = GeneratedColumn<int>(
      'course_version_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _fromKpKeyMeta =
      const VerificationMeta('fromKpKey');
  @override
  late final GeneratedColumn<String> fromKpKey = GeneratedColumn<String>(
      'from_kp_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _toKpKeyMeta =
      const VerificationMeta('toKpKey');
  @override
  late final GeneratedColumn<String> toKpKey = GeneratedColumn<String>(
      'to_kp_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, courseVersionId, fromKpKey, toKpKey];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'course_edges';
  @override
  VerificationContext validateIntegrity(Insertable<CourseEdge> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('course_version_id')) {
      context.handle(
          _courseVersionIdMeta,
          courseVersionId.isAcceptableOrUnknown(
              data['course_version_id']!, _courseVersionIdMeta));
    } else if (isInserting) {
      context.missing(_courseVersionIdMeta);
    }
    if (data.containsKey('from_kp_key')) {
      context.handle(
          _fromKpKeyMeta,
          fromKpKey.isAcceptableOrUnknown(
              data['from_kp_key']!, _fromKpKeyMeta));
    } else if (isInserting) {
      context.missing(_fromKpKeyMeta);
    }
    if (data.containsKey('to_kp_key')) {
      context.handle(_toKpKeyMeta,
          toKpKey.isAcceptableOrUnknown(data['to_kp_key']!, _toKpKeyMeta));
    } else if (isInserting) {
      context.missing(_toKpKeyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CourseEdge map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CourseEdge(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      courseVersionId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}course_version_id'])!,
      fromKpKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}from_kp_key'])!,
      toKpKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}to_kp_key'])!,
    );
  }

  @override
  $CourseEdgesTable createAlias(String alias) {
    return $CourseEdgesTable(attachedDatabase, alias);
  }
}

class CourseEdge extends DataClass implements Insertable<CourseEdge> {
  final int id;
  final int courseVersionId;
  final String fromKpKey;
  final String toKpKey;
  const CourseEdge(
      {required this.id,
      required this.courseVersionId,
      required this.fromKpKey,
      required this.toKpKey});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['course_version_id'] = Variable<int>(courseVersionId);
    map['from_kp_key'] = Variable<String>(fromKpKey);
    map['to_kp_key'] = Variable<String>(toKpKey);
    return map;
  }

  CourseEdgesCompanion toCompanion(bool nullToAbsent) {
    return CourseEdgesCompanion(
      id: Value(id),
      courseVersionId: Value(courseVersionId),
      fromKpKey: Value(fromKpKey),
      toKpKey: Value(toKpKey),
    );
  }

  factory CourseEdge.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CourseEdge(
      id: serializer.fromJson<int>(json['id']),
      courseVersionId: serializer.fromJson<int>(json['courseVersionId']),
      fromKpKey: serializer.fromJson<String>(json['fromKpKey']),
      toKpKey: serializer.fromJson<String>(json['toKpKey']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'courseVersionId': serializer.toJson<int>(courseVersionId),
      'fromKpKey': serializer.toJson<String>(fromKpKey),
      'toKpKey': serializer.toJson<String>(toKpKey),
    };
  }

  CourseEdge copyWith(
          {int? id,
          int? courseVersionId,
          String? fromKpKey,
          String? toKpKey}) =>
      CourseEdge(
        id: id ?? this.id,
        courseVersionId: courseVersionId ?? this.courseVersionId,
        fromKpKey: fromKpKey ?? this.fromKpKey,
        toKpKey: toKpKey ?? this.toKpKey,
      );
  CourseEdge copyWithCompanion(CourseEdgesCompanion data) {
    return CourseEdge(
      id: data.id.present ? data.id.value : this.id,
      courseVersionId: data.courseVersionId.present
          ? data.courseVersionId.value
          : this.courseVersionId,
      fromKpKey: data.fromKpKey.present ? data.fromKpKey.value : this.fromKpKey,
      toKpKey: data.toKpKey.present ? data.toKpKey.value : this.toKpKey,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CourseEdge(')
          ..write('id: $id, ')
          ..write('courseVersionId: $courseVersionId, ')
          ..write('fromKpKey: $fromKpKey, ')
          ..write('toKpKey: $toKpKey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, courseVersionId, fromKpKey, toKpKey);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CourseEdge &&
          other.id == this.id &&
          other.courseVersionId == this.courseVersionId &&
          other.fromKpKey == this.fromKpKey &&
          other.toKpKey == this.toKpKey);
}

class CourseEdgesCompanion extends UpdateCompanion<CourseEdge> {
  final Value<int> id;
  final Value<int> courseVersionId;
  final Value<String> fromKpKey;
  final Value<String> toKpKey;
  const CourseEdgesCompanion({
    this.id = const Value.absent(),
    this.courseVersionId = const Value.absent(),
    this.fromKpKey = const Value.absent(),
    this.toKpKey = const Value.absent(),
  });
  CourseEdgesCompanion.insert({
    this.id = const Value.absent(),
    required int courseVersionId,
    required String fromKpKey,
    required String toKpKey,
  })  : courseVersionId = Value(courseVersionId),
        fromKpKey = Value(fromKpKey),
        toKpKey = Value(toKpKey);
  static Insertable<CourseEdge> custom({
    Expression<int>? id,
    Expression<int>? courseVersionId,
    Expression<String>? fromKpKey,
    Expression<String>? toKpKey,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (courseVersionId != null) 'course_version_id': courseVersionId,
      if (fromKpKey != null) 'from_kp_key': fromKpKey,
      if (toKpKey != null) 'to_kp_key': toKpKey,
    });
  }

  CourseEdgesCompanion copyWith(
      {Value<int>? id,
      Value<int>? courseVersionId,
      Value<String>? fromKpKey,
      Value<String>? toKpKey}) {
    return CourseEdgesCompanion(
      id: id ?? this.id,
      courseVersionId: courseVersionId ?? this.courseVersionId,
      fromKpKey: fromKpKey ?? this.fromKpKey,
      toKpKey: toKpKey ?? this.toKpKey,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (courseVersionId.present) {
      map['course_version_id'] = Variable<int>(courseVersionId.value);
    }
    if (fromKpKey.present) {
      map['from_kp_key'] = Variable<String>(fromKpKey.value);
    }
    if (toKpKey.present) {
      map['to_kp_key'] = Variable<String>(toKpKey.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CourseEdgesCompanion(')
          ..write('id: $id, ')
          ..write('courseVersionId: $courseVersionId, ')
          ..write('fromKpKey: $fromKpKey, ')
          ..write('toKpKey: $toKpKey')
          ..write(')'))
        .toString();
  }
}

class $StudentCourseAssignmentsTable extends StudentCourseAssignments
    with TableInfo<$StudentCourseAssignmentsTable, StudentCourseAssignment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StudentCourseAssignmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _studentIdMeta =
      const VerificationMeta('studentId');
  @override
  late final GeneratedColumn<int> studentId = GeneratedColumn<int>(
      'student_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _courseVersionIdMeta =
      const VerificationMeta('courseVersionId');
  @override
  late final GeneratedColumn<int> courseVersionId = GeneratedColumn<int>(
      'course_version_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _assignedAtMeta =
      const VerificationMeta('assignedAt');
  @override
  late final GeneratedColumn<DateTime> assignedAt = GeneratedColumn<DateTime>(
      'assigned_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns =>
      [id, studentId, courseVersionId, assignedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'student_course_assignments';
  @override
  VerificationContext validateIntegrity(
      Insertable<StudentCourseAssignment> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('student_id')) {
      context.handle(_studentIdMeta,
          studentId.isAcceptableOrUnknown(data['student_id']!, _studentIdMeta));
    } else if (isInserting) {
      context.missing(_studentIdMeta);
    }
    if (data.containsKey('course_version_id')) {
      context.handle(
          _courseVersionIdMeta,
          courseVersionId.isAcceptableOrUnknown(
              data['course_version_id']!, _courseVersionIdMeta));
    } else if (isInserting) {
      context.missing(_courseVersionIdMeta);
    }
    if (data.containsKey('assigned_at')) {
      context.handle(
          _assignedAtMeta,
          assignedAt.isAcceptableOrUnknown(
              data['assigned_at']!, _assignedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
        {studentId, courseVersionId},
      ];
  @override
  StudentCourseAssignment map(Map<String, dynamic> data,
      {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StudentCourseAssignment(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      studentId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}student_id'])!,
      courseVersionId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}course_version_id'])!,
      assignedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}assigned_at'])!,
    );
  }

  @override
  $StudentCourseAssignmentsTable createAlias(String alias) {
    return $StudentCourseAssignmentsTable(attachedDatabase, alias);
  }
}

class StudentCourseAssignment extends DataClass
    implements Insertable<StudentCourseAssignment> {
  final int id;
  final int studentId;
  final int courseVersionId;
  final DateTime assignedAt;
  const StudentCourseAssignment(
      {required this.id,
      required this.studentId,
      required this.courseVersionId,
      required this.assignedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['student_id'] = Variable<int>(studentId);
    map['course_version_id'] = Variable<int>(courseVersionId);
    map['assigned_at'] = Variable<DateTime>(assignedAt);
    return map;
  }

  StudentCourseAssignmentsCompanion toCompanion(bool nullToAbsent) {
    return StudentCourseAssignmentsCompanion(
      id: Value(id),
      studentId: Value(studentId),
      courseVersionId: Value(courseVersionId),
      assignedAt: Value(assignedAt),
    );
  }

  factory StudentCourseAssignment.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StudentCourseAssignment(
      id: serializer.fromJson<int>(json['id']),
      studentId: serializer.fromJson<int>(json['studentId']),
      courseVersionId: serializer.fromJson<int>(json['courseVersionId']),
      assignedAt: serializer.fromJson<DateTime>(json['assignedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'studentId': serializer.toJson<int>(studentId),
      'courseVersionId': serializer.toJson<int>(courseVersionId),
      'assignedAt': serializer.toJson<DateTime>(assignedAt),
    };
  }

  StudentCourseAssignment copyWith(
          {int? id,
          int? studentId,
          int? courseVersionId,
          DateTime? assignedAt}) =>
      StudentCourseAssignment(
        id: id ?? this.id,
        studentId: studentId ?? this.studentId,
        courseVersionId: courseVersionId ?? this.courseVersionId,
        assignedAt: assignedAt ?? this.assignedAt,
      );
  StudentCourseAssignment copyWithCompanion(
      StudentCourseAssignmentsCompanion data) {
    return StudentCourseAssignment(
      id: data.id.present ? data.id.value : this.id,
      studentId: data.studentId.present ? data.studentId.value : this.studentId,
      courseVersionId: data.courseVersionId.present
          ? data.courseVersionId.value
          : this.courseVersionId,
      assignedAt:
          data.assignedAt.present ? data.assignedAt.value : this.assignedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StudentCourseAssignment(')
          ..write('id: $id, ')
          ..write('studentId: $studentId, ')
          ..write('courseVersionId: $courseVersionId, ')
          ..write('assignedAt: $assignedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, studentId, courseVersionId, assignedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StudentCourseAssignment &&
          other.id == this.id &&
          other.studentId == this.studentId &&
          other.courseVersionId == this.courseVersionId &&
          other.assignedAt == this.assignedAt);
}

class StudentCourseAssignmentsCompanion
    extends UpdateCompanion<StudentCourseAssignment> {
  final Value<int> id;
  final Value<int> studentId;
  final Value<int> courseVersionId;
  final Value<DateTime> assignedAt;
  const StudentCourseAssignmentsCompanion({
    this.id = const Value.absent(),
    this.studentId = const Value.absent(),
    this.courseVersionId = const Value.absent(),
    this.assignedAt = const Value.absent(),
  });
  StudentCourseAssignmentsCompanion.insert({
    this.id = const Value.absent(),
    required int studentId,
    required int courseVersionId,
    this.assignedAt = const Value.absent(),
  })  : studentId = Value(studentId),
        courseVersionId = Value(courseVersionId);
  static Insertable<StudentCourseAssignment> custom({
    Expression<int>? id,
    Expression<int>? studentId,
    Expression<int>? courseVersionId,
    Expression<DateTime>? assignedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (studentId != null) 'student_id': studentId,
      if (courseVersionId != null) 'course_version_id': courseVersionId,
      if (assignedAt != null) 'assigned_at': assignedAt,
    });
  }

  StudentCourseAssignmentsCompanion copyWith(
      {Value<int>? id,
      Value<int>? studentId,
      Value<int>? courseVersionId,
      Value<DateTime>? assignedAt}) {
    return StudentCourseAssignmentsCompanion(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      courseVersionId: courseVersionId ?? this.courseVersionId,
      assignedAt: assignedAt ?? this.assignedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (studentId.present) {
      map['student_id'] = Variable<int>(studentId.value);
    }
    if (courseVersionId.present) {
      map['course_version_id'] = Variable<int>(courseVersionId.value);
    }
    if (assignedAt.present) {
      map['assigned_at'] = Variable<DateTime>(assignedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StudentCourseAssignmentsCompanion(')
          ..write('id: $id, ')
          ..write('studentId: $studentId, ')
          ..write('courseVersionId: $courseVersionId, ')
          ..write('assignedAt: $assignedAt')
          ..write(')'))
        .toString();
  }
}

class $ProgressEntriesTable extends ProgressEntries
    with TableInfo<$ProgressEntriesTable, ProgressEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProgressEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _studentIdMeta =
      const VerificationMeta('studentId');
  @override
  late final GeneratedColumn<int> studentId = GeneratedColumn<int>(
      'student_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _courseVersionIdMeta =
      const VerificationMeta('courseVersionId');
  @override
  late final GeneratedColumn<int> courseVersionId = GeneratedColumn<int>(
      'course_version_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _kpKeyMeta = const VerificationMeta('kpKey');
  @override
  late final GeneratedColumn<String> kpKey = GeneratedColumn<String>(
      'kp_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _litMeta = const VerificationMeta('lit');
  @override
  late final GeneratedColumn<bool> lit = GeneratedColumn<bool>(
      'lit', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("lit" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _litPercentMeta =
      const VerificationMeta('litPercent');
  @override
  late final GeneratedColumn<int> litPercent = GeneratedColumn<int>(
      'lit_percent', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _questionLevelMeta =
      const VerificationMeta('questionLevel');
  @override
  late final GeneratedColumn<String> questionLevel = GeneratedColumn<String>(
      'question_level', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _summaryTextMeta =
      const VerificationMeta('summaryText');
  @override
  late final GeneratedColumn<String> summaryText = GeneratedColumn<String>(
      'summary_text', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _summaryRawResponseMeta =
      const VerificationMeta('summaryRawResponse');
  @override
  late final GeneratedColumn<String> summaryRawResponse =
      GeneratedColumn<String>('summary_raw_response', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _summaryValidMeta =
      const VerificationMeta('summaryValid');
  @override
  late final GeneratedColumn<bool> summaryValid = GeneratedColumn<bool>(
      'summary_valid', aliasedName, true,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("summary_valid" IN (0, 1))'));
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        studentId,
        courseVersionId,
        kpKey,
        lit,
        litPercent,
        questionLevel,
        summaryText,
        summaryRawResponse,
        summaryValid,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'progress_entries';
  @override
  VerificationContext validateIntegrity(Insertable<ProgressEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('student_id')) {
      context.handle(_studentIdMeta,
          studentId.isAcceptableOrUnknown(data['student_id']!, _studentIdMeta));
    } else if (isInserting) {
      context.missing(_studentIdMeta);
    }
    if (data.containsKey('course_version_id')) {
      context.handle(
          _courseVersionIdMeta,
          courseVersionId.isAcceptableOrUnknown(
              data['course_version_id']!, _courseVersionIdMeta));
    } else if (isInserting) {
      context.missing(_courseVersionIdMeta);
    }
    if (data.containsKey('kp_key')) {
      context.handle(
          _kpKeyMeta, kpKey.isAcceptableOrUnknown(data['kp_key']!, _kpKeyMeta));
    } else if (isInserting) {
      context.missing(_kpKeyMeta);
    }
    if (data.containsKey('lit')) {
      context.handle(
          _litMeta, lit.isAcceptableOrUnknown(data['lit']!, _litMeta));
    }
    if (data.containsKey('lit_percent')) {
      context.handle(
          _litPercentMeta,
          litPercent.isAcceptableOrUnknown(
              data['lit_percent']!, _litPercentMeta));
    }
    if (data.containsKey('question_level')) {
      context.handle(
          _questionLevelMeta,
          questionLevel.isAcceptableOrUnknown(
              data['question_level']!, _questionLevelMeta));
    }
    if (data.containsKey('summary_text')) {
      context.handle(
          _summaryTextMeta,
          summaryText.isAcceptableOrUnknown(
              data['summary_text']!, _summaryTextMeta));
    }
    if (data.containsKey('summary_raw_response')) {
      context.handle(
          _summaryRawResponseMeta,
          summaryRawResponse.isAcceptableOrUnknown(
              data['summary_raw_response']!, _summaryRawResponseMeta));
    }
    if (data.containsKey('summary_valid')) {
      context.handle(
          _summaryValidMeta,
          summaryValid.isAcceptableOrUnknown(
              data['summary_valid']!, _summaryValidMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
        {studentId, courseVersionId, kpKey},
      ];
  @override
  ProgressEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProgressEntry(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      studentId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}student_id'])!,
      courseVersionId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}course_version_id'])!,
      kpKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}kp_key'])!,
      lit: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}lit'])!,
      litPercent: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}lit_percent'])!,
      questionLevel: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}question_level']),
      summaryText: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}summary_text']),
      summaryRawResponse: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}summary_raw_response']),
      summaryValid: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}summary_valid']),
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $ProgressEntriesTable createAlias(String alias) {
    return $ProgressEntriesTable(attachedDatabase, alias);
  }
}

class ProgressEntry extends DataClass implements Insertable<ProgressEntry> {
  final int id;
  final int studentId;
  final int courseVersionId;
  final String kpKey;
  final bool lit;
  final int litPercent;
  final String? questionLevel;
  final String? summaryText;
  final String? summaryRawResponse;
  final bool? summaryValid;
  final DateTime updatedAt;
  const ProgressEntry(
      {required this.id,
      required this.studentId,
      required this.courseVersionId,
      required this.kpKey,
      required this.lit,
      required this.litPercent,
      this.questionLevel,
      this.summaryText,
      this.summaryRawResponse,
      this.summaryValid,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['student_id'] = Variable<int>(studentId);
    map['course_version_id'] = Variable<int>(courseVersionId);
    map['kp_key'] = Variable<String>(kpKey);
    map['lit'] = Variable<bool>(lit);
    map['lit_percent'] = Variable<int>(litPercent);
    if (!nullToAbsent || questionLevel != null) {
      map['question_level'] = Variable<String>(questionLevel);
    }
    if (!nullToAbsent || summaryText != null) {
      map['summary_text'] = Variable<String>(summaryText);
    }
    if (!nullToAbsent || summaryRawResponse != null) {
      map['summary_raw_response'] = Variable<String>(summaryRawResponse);
    }
    if (!nullToAbsent || summaryValid != null) {
      map['summary_valid'] = Variable<bool>(summaryValid);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ProgressEntriesCompanion toCompanion(bool nullToAbsent) {
    return ProgressEntriesCompanion(
      id: Value(id),
      studentId: Value(studentId),
      courseVersionId: Value(courseVersionId),
      kpKey: Value(kpKey),
      lit: Value(lit),
      litPercent: Value(litPercent),
      questionLevel: questionLevel == null && nullToAbsent
          ? const Value.absent()
          : Value(questionLevel),
      summaryText: summaryText == null && nullToAbsent
          ? const Value.absent()
          : Value(summaryText),
      summaryRawResponse: summaryRawResponse == null && nullToAbsent
          ? const Value.absent()
          : Value(summaryRawResponse),
      summaryValid: summaryValid == null && nullToAbsent
          ? const Value.absent()
          : Value(summaryValid),
      updatedAt: Value(updatedAt),
    );
  }

  factory ProgressEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProgressEntry(
      id: serializer.fromJson<int>(json['id']),
      studentId: serializer.fromJson<int>(json['studentId']),
      courseVersionId: serializer.fromJson<int>(json['courseVersionId']),
      kpKey: serializer.fromJson<String>(json['kpKey']),
      lit: serializer.fromJson<bool>(json['lit']),
      litPercent: serializer.fromJson<int>(json['litPercent']),
      questionLevel: serializer.fromJson<String?>(json['questionLevel']),
      summaryText: serializer.fromJson<String?>(json['summaryText']),
      summaryRawResponse:
          serializer.fromJson<String?>(json['summaryRawResponse']),
      summaryValid: serializer.fromJson<bool?>(json['summaryValid']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'studentId': serializer.toJson<int>(studentId),
      'courseVersionId': serializer.toJson<int>(courseVersionId),
      'kpKey': serializer.toJson<String>(kpKey),
      'lit': serializer.toJson<bool>(lit),
      'litPercent': serializer.toJson<int>(litPercent),
      'questionLevel': serializer.toJson<String?>(questionLevel),
      'summaryText': serializer.toJson<String?>(summaryText),
      'summaryRawResponse': serializer.toJson<String?>(summaryRawResponse),
      'summaryValid': serializer.toJson<bool?>(summaryValid),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ProgressEntry copyWith(
          {int? id,
          int? studentId,
          int? courseVersionId,
          String? kpKey,
          bool? lit,
          int? litPercent,
          Value<String?> questionLevel = const Value.absent(),
          Value<String?> summaryText = const Value.absent(),
          Value<String?> summaryRawResponse = const Value.absent(),
          Value<bool?> summaryValid = const Value.absent(),
          DateTime? updatedAt}) =>
      ProgressEntry(
        id: id ?? this.id,
        studentId: studentId ?? this.studentId,
        courseVersionId: courseVersionId ?? this.courseVersionId,
        kpKey: kpKey ?? this.kpKey,
        lit: lit ?? this.lit,
        litPercent: litPercent ?? this.litPercent,
        questionLevel:
            questionLevel.present ? questionLevel.value : this.questionLevel,
        summaryText: summaryText.present ? summaryText.value : this.summaryText,
        summaryRawResponse: summaryRawResponse.present
            ? summaryRawResponse.value
            : this.summaryRawResponse,
        summaryValid:
            summaryValid.present ? summaryValid.value : this.summaryValid,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  ProgressEntry copyWithCompanion(ProgressEntriesCompanion data) {
    return ProgressEntry(
      id: data.id.present ? data.id.value : this.id,
      studentId: data.studentId.present ? data.studentId.value : this.studentId,
      courseVersionId: data.courseVersionId.present
          ? data.courseVersionId.value
          : this.courseVersionId,
      kpKey: data.kpKey.present ? data.kpKey.value : this.kpKey,
      lit: data.lit.present ? data.lit.value : this.lit,
      litPercent:
          data.litPercent.present ? data.litPercent.value : this.litPercent,
      questionLevel: data.questionLevel.present
          ? data.questionLevel.value
          : this.questionLevel,
      summaryText:
          data.summaryText.present ? data.summaryText.value : this.summaryText,
      summaryRawResponse: data.summaryRawResponse.present
          ? data.summaryRawResponse.value
          : this.summaryRawResponse,
      summaryValid: data.summaryValid.present
          ? data.summaryValid.value
          : this.summaryValid,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProgressEntry(')
          ..write('id: $id, ')
          ..write('studentId: $studentId, ')
          ..write('courseVersionId: $courseVersionId, ')
          ..write('kpKey: $kpKey, ')
          ..write('lit: $lit, ')
          ..write('litPercent: $litPercent, ')
          ..write('questionLevel: $questionLevel, ')
          ..write('summaryText: $summaryText, ')
          ..write('summaryRawResponse: $summaryRawResponse, ')
          ..write('summaryValid: $summaryValid, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      studentId,
      courseVersionId,
      kpKey,
      lit,
      litPercent,
      questionLevel,
      summaryText,
      summaryRawResponse,
      summaryValid,
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProgressEntry &&
          other.id == this.id &&
          other.studentId == this.studentId &&
          other.courseVersionId == this.courseVersionId &&
          other.kpKey == this.kpKey &&
          other.lit == this.lit &&
          other.litPercent == this.litPercent &&
          other.questionLevel == this.questionLevel &&
          other.summaryText == this.summaryText &&
          other.summaryRawResponse == this.summaryRawResponse &&
          other.summaryValid == this.summaryValid &&
          other.updatedAt == this.updatedAt);
}

class ProgressEntriesCompanion extends UpdateCompanion<ProgressEntry> {
  final Value<int> id;
  final Value<int> studentId;
  final Value<int> courseVersionId;
  final Value<String> kpKey;
  final Value<bool> lit;
  final Value<int> litPercent;
  final Value<String?> questionLevel;
  final Value<String?> summaryText;
  final Value<String?> summaryRawResponse;
  final Value<bool?> summaryValid;
  final Value<DateTime> updatedAt;
  const ProgressEntriesCompanion({
    this.id = const Value.absent(),
    this.studentId = const Value.absent(),
    this.courseVersionId = const Value.absent(),
    this.kpKey = const Value.absent(),
    this.lit = const Value.absent(),
    this.litPercent = const Value.absent(),
    this.questionLevel = const Value.absent(),
    this.summaryText = const Value.absent(),
    this.summaryRawResponse = const Value.absent(),
    this.summaryValid = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  ProgressEntriesCompanion.insert({
    this.id = const Value.absent(),
    required int studentId,
    required int courseVersionId,
    required String kpKey,
    this.lit = const Value.absent(),
    this.litPercent = const Value.absent(),
    this.questionLevel = const Value.absent(),
    this.summaryText = const Value.absent(),
    this.summaryRawResponse = const Value.absent(),
    this.summaryValid = const Value.absent(),
    this.updatedAt = const Value.absent(),
  })  : studentId = Value(studentId),
        courseVersionId = Value(courseVersionId),
        kpKey = Value(kpKey);
  static Insertable<ProgressEntry> custom({
    Expression<int>? id,
    Expression<int>? studentId,
    Expression<int>? courseVersionId,
    Expression<String>? kpKey,
    Expression<bool>? lit,
    Expression<int>? litPercent,
    Expression<String>? questionLevel,
    Expression<String>? summaryText,
    Expression<String>? summaryRawResponse,
    Expression<bool>? summaryValid,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (studentId != null) 'student_id': studentId,
      if (courseVersionId != null) 'course_version_id': courseVersionId,
      if (kpKey != null) 'kp_key': kpKey,
      if (lit != null) 'lit': lit,
      if (litPercent != null) 'lit_percent': litPercent,
      if (questionLevel != null) 'question_level': questionLevel,
      if (summaryText != null) 'summary_text': summaryText,
      if (summaryRawResponse != null)
        'summary_raw_response': summaryRawResponse,
      if (summaryValid != null) 'summary_valid': summaryValid,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  ProgressEntriesCompanion copyWith(
      {Value<int>? id,
      Value<int>? studentId,
      Value<int>? courseVersionId,
      Value<String>? kpKey,
      Value<bool>? lit,
      Value<int>? litPercent,
      Value<String?>? questionLevel,
      Value<String?>? summaryText,
      Value<String?>? summaryRawResponse,
      Value<bool?>? summaryValid,
      Value<DateTime>? updatedAt}) {
    return ProgressEntriesCompanion(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      courseVersionId: courseVersionId ?? this.courseVersionId,
      kpKey: kpKey ?? this.kpKey,
      lit: lit ?? this.lit,
      litPercent: litPercent ?? this.litPercent,
      questionLevel: questionLevel ?? this.questionLevel,
      summaryText: summaryText ?? this.summaryText,
      summaryRawResponse: summaryRawResponse ?? this.summaryRawResponse,
      summaryValid: summaryValid ?? this.summaryValid,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (studentId.present) {
      map['student_id'] = Variable<int>(studentId.value);
    }
    if (courseVersionId.present) {
      map['course_version_id'] = Variable<int>(courseVersionId.value);
    }
    if (kpKey.present) {
      map['kp_key'] = Variable<String>(kpKey.value);
    }
    if (lit.present) {
      map['lit'] = Variable<bool>(lit.value);
    }
    if (litPercent.present) {
      map['lit_percent'] = Variable<int>(litPercent.value);
    }
    if (questionLevel.present) {
      map['question_level'] = Variable<String>(questionLevel.value);
    }
    if (summaryText.present) {
      map['summary_text'] = Variable<String>(summaryText.value);
    }
    if (summaryRawResponse.present) {
      map['summary_raw_response'] = Variable<String>(summaryRawResponse.value);
    }
    if (summaryValid.present) {
      map['summary_valid'] = Variable<bool>(summaryValid.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProgressEntriesCompanion(')
          ..write('id: $id, ')
          ..write('studentId: $studentId, ')
          ..write('courseVersionId: $courseVersionId, ')
          ..write('kpKey: $kpKey, ')
          ..write('lit: $lit, ')
          ..write('litPercent: $litPercent, ')
          ..write('questionLevel: $questionLevel, ')
          ..write('summaryText: $summaryText, ')
          ..write('summaryRawResponse: $summaryRawResponse, ')
          ..write('summaryValid: $summaryValid, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $ChatSessionsTable extends ChatSessions
    with TableInfo<$ChatSessionsTable, ChatSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _studentIdMeta =
      const VerificationMeta('studentId');
  @override
  late final GeneratedColumn<int> studentId = GeneratedColumn<int>(
      'student_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _courseVersionIdMeta =
      const VerificationMeta('courseVersionId');
  @override
  late final GeneratedColumn<int> courseVersionId = GeneratedColumn<int>(
      'course_version_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _kpKeyMeta = const VerificationMeta('kpKey');
  @override
  late final GeneratedColumn<String> kpKey = GeneratedColumn<String>(
      'kp_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _startedAtMeta =
      const VerificationMeta('startedAt');
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
      'started_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _endedAtMeta =
      const VerificationMeta('endedAt');
  @override
  late final GeneratedColumn<DateTime> endedAt = GeneratedColumn<DateTime>(
      'ended_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('active'));
  static const VerificationMeta _summaryTextMeta =
      const VerificationMeta('summaryText');
  @override
  late final GeneratedColumn<String> summaryText = GeneratedColumn<String>(
      'summary_text', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _summaryLitMeta =
      const VerificationMeta('summaryLit');
  @override
  late final GeneratedColumn<bool> summaryLit = GeneratedColumn<bool>(
      'summary_lit', aliasedName, true,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("summary_lit" IN (0, 1))'));
  static const VerificationMeta _summaryLitPercentMeta =
      const VerificationMeta('summaryLitPercent');
  @override
  late final GeneratedColumn<int> summaryLitPercent = GeneratedColumn<int>(
      'summary_lit_percent', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _summaryRawResponseMeta =
      const VerificationMeta('summaryRawResponse');
  @override
  late final GeneratedColumn<String> summaryRawResponse =
      GeneratedColumn<String>('summary_raw_response', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _summaryValidMeta =
      const VerificationMeta('summaryValid');
  @override
  late final GeneratedColumn<bool> summaryValid = GeneratedColumn<bool>(
      'summary_valid', aliasedName, true,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("summary_valid" IN (0, 1))'));
  static const VerificationMeta _summarizeCallIdMeta =
      const VerificationMeta('summarizeCallId');
  @override
  late final GeneratedColumn<int> summarizeCallId = GeneratedColumn<int>(
      'summarize_call_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _controlStateJsonMeta =
      const VerificationMeta('controlStateJson');
  @override
  late final GeneratedColumn<String> controlStateJson = GeneratedColumn<String>(
      'control_state_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _controlStateUpdatedAtMeta =
      const VerificationMeta('controlStateUpdatedAt');
  @override
  late final GeneratedColumn<DateTime> controlStateUpdatedAt =
      GeneratedColumn<DateTime>('control_state_updated_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _evidenceStateJsonMeta =
      const VerificationMeta('evidenceStateJson');
  @override
  late final GeneratedColumn<String> evidenceStateJson =
      GeneratedColumn<String>('evidence_state_json', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _evidenceStateUpdatedAtMeta =
      const VerificationMeta('evidenceStateUpdatedAt');
  @override
  late final GeneratedColumn<DateTime> evidenceStateUpdatedAt =
      GeneratedColumn<DateTime>('evidence_state_updated_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _syncIdMeta = const VerificationMeta('syncId');
  @override
  late final GeneratedColumn<String> syncId = GeneratedColumn<String>(
      'sync_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _syncUpdatedAtMeta =
      const VerificationMeta('syncUpdatedAt');
  @override
  late final GeneratedColumn<DateTime> syncUpdatedAt =
      GeneratedColumn<DateTime>('sync_updated_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _syncUploadedAtMeta =
      const VerificationMeta('syncUploadedAt');
  @override
  late final GeneratedColumn<DateTime> syncUploadedAt =
      GeneratedColumn<DateTime>('sync_uploaded_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        studentId,
        courseVersionId,
        kpKey,
        title,
        startedAt,
        endedAt,
        status,
        summaryText,
        summaryLit,
        summaryLitPercent,
        summaryRawResponse,
        summaryValid,
        summarizeCallId,
        controlStateJson,
        controlStateUpdatedAt,
        evidenceStateJson,
        evidenceStateUpdatedAt,
        syncId,
        syncUpdatedAt,
        syncUploadedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_sessions';
  @override
  VerificationContext validateIntegrity(Insertable<ChatSession> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('student_id')) {
      context.handle(_studentIdMeta,
          studentId.isAcceptableOrUnknown(data['student_id']!, _studentIdMeta));
    } else if (isInserting) {
      context.missing(_studentIdMeta);
    }
    if (data.containsKey('course_version_id')) {
      context.handle(
          _courseVersionIdMeta,
          courseVersionId.isAcceptableOrUnknown(
              data['course_version_id']!, _courseVersionIdMeta));
    } else if (isInserting) {
      context.missing(_courseVersionIdMeta);
    }
    if (data.containsKey('kp_key')) {
      context.handle(
          _kpKeyMeta, kpKey.isAcceptableOrUnknown(data['kp_key']!, _kpKeyMeta));
    } else if (isInserting) {
      context.missing(_kpKeyMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    }
    if (data.containsKey('started_at')) {
      context.handle(_startedAtMeta,
          startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta));
    }
    if (data.containsKey('ended_at')) {
      context.handle(_endedAtMeta,
          endedAt.isAcceptableOrUnknown(data['ended_at']!, _endedAtMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('summary_text')) {
      context.handle(
          _summaryTextMeta,
          summaryText.isAcceptableOrUnknown(
              data['summary_text']!, _summaryTextMeta));
    }
    if (data.containsKey('summary_lit')) {
      context.handle(
          _summaryLitMeta,
          summaryLit.isAcceptableOrUnknown(
              data['summary_lit']!, _summaryLitMeta));
    }
    if (data.containsKey('summary_lit_percent')) {
      context.handle(
          _summaryLitPercentMeta,
          summaryLitPercent.isAcceptableOrUnknown(
              data['summary_lit_percent']!, _summaryLitPercentMeta));
    }
    if (data.containsKey('summary_raw_response')) {
      context.handle(
          _summaryRawResponseMeta,
          summaryRawResponse.isAcceptableOrUnknown(
              data['summary_raw_response']!, _summaryRawResponseMeta));
    }
    if (data.containsKey('summary_valid')) {
      context.handle(
          _summaryValidMeta,
          summaryValid.isAcceptableOrUnknown(
              data['summary_valid']!, _summaryValidMeta));
    }
    if (data.containsKey('summarize_call_id')) {
      context.handle(
          _summarizeCallIdMeta,
          summarizeCallId.isAcceptableOrUnknown(
              data['summarize_call_id']!, _summarizeCallIdMeta));
    }
    if (data.containsKey('control_state_json')) {
      context.handle(
          _controlStateJsonMeta,
          controlStateJson.isAcceptableOrUnknown(
              data['control_state_json']!, _controlStateJsonMeta));
    }
    if (data.containsKey('control_state_updated_at')) {
      context.handle(
          _controlStateUpdatedAtMeta,
          controlStateUpdatedAt.isAcceptableOrUnknown(
              data['control_state_updated_at']!, _controlStateUpdatedAtMeta));
    }
    if (data.containsKey('evidence_state_json')) {
      context.handle(
          _evidenceStateJsonMeta,
          evidenceStateJson.isAcceptableOrUnknown(
              data['evidence_state_json']!, _evidenceStateJsonMeta));
    }
    if (data.containsKey('evidence_state_updated_at')) {
      context.handle(
          _evidenceStateUpdatedAtMeta,
          evidenceStateUpdatedAt.isAcceptableOrUnknown(
              data['evidence_state_updated_at']!, _evidenceStateUpdatedAtMeta));
    }
    if (data.containsKey('sync_id')) {
      context.handle(_syncIdMeta,
          syncId.isAcceptableOrUnknown(data['sync_id']!, _syncIdMeta));
    }
    if (data.containsKey('sync_updated_at')) {
      context.handle(
          _syncUpdatedAtMeta,
          syncUpdatedAt.isAcceptableOrUnknown(
              data['sync_updated_at']!, _syncUpdatedAtMeta));
    }
    if (data.containsKey('sync_uploaded_at')) {
      context.handle(
          _syncUploadedAtMeta,
          syncUploadedAt.isAcceptableOrUnknown(
              data['sync_uploaded_at']!, _syncUploadedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ChatSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatSession(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      studentId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}student_id'])!,
      courseVersionId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}course_version_id'])!,
      kpKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}kp_key'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title']),
      startedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}started_at'])!,
      endedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}ended_at']),
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      summaryText: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}summary_text']),
      summaryLit: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}summary_lit']),
      summaryLitPercent: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}summary_lit_percent']),
      summaryRawResponse: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}summary_raw_response']),
      summaryValid: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}summary_valid']),
      summarizeCallId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}summarize_call_id']),
      controlStateJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}control_state_json']),
      controlStateUpdatedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime,
          data['${effectivePrefix}control_state_updated_at']),
      evidenceStateJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}evidence_state_json']),
      evidenceStateUpdatedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime,
          data['${effectivePrefix}evidence_state_updated_at']),
      syncId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sync_id']),
      syncUpdatedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}sync_updated_at']),
      syncUploadedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}sync_uploaded_at']),
    );
  }

  @override
  $ChatSessionsTable createAlias(String alias) {
    return $ChatSessionsTable(attachedDatabase, alias);
  }
}

class ChatSession extends DataClass implements Insertable<ChatSession> {
  final int id;
  final int studentId;
  final int courseVersionId;
  final String kpKey;
  final String? title;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String status;
  final String? summaryText;
  final bool? summaryLit;
  final int? summaryLitPercent;
  final String? summaryRawResponse;
  final bool? summaryValid;
  final int? summarizeCallId;
  final String? controlStateJson;
  final DateTime? controlStateUpdatedAt;
  final String? evidenceStateJson;
  final DateTime? evidenceStateUpdatedAt;
  final String? syncId;
  final DateTime? syncUpdatedAt;
  final DateTime? syncUploadedAt;
  const ChatSession(
      {required this.id,
      required this.studentId,
      required this.courseVersionId,
      required this.kpKey,
      this.title,
      required this.startedAt,
      this.endedAt,
      required this.status,
      this.summaryText,
      this.summaryLit,
      this.summaryLitPercent,
      this.summaryRawResponse,
      this.summaryValid,
      this.summarizeCallId,
      this.controlStateJson,
      this.controlStateUpdatedAt,
      this.evidenceStateJson,
      this.evidenceStateUpdatedAt,
      this.syncId,
      this.syncUpdatedAt,
      this.syncUploadedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['student_id'] = Variable<int>(studentId);
    map['course_version_id'] = Variable<int>(courseVersionId);
    map['kp_key'] = Variable<String>(kpKey);
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    map['started_at'] = Variable<DateTime>(startedAt);
    if (!nullToAbsent || endedAt != null) {
      map['ended_at'] = Variable<DateTime>(endedAt);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || summaryText != null) {
      map['summary_text'] = Variable<String>(summaryText);
    }
    if (!nullToAbsent || summaryLit != null) {
      map['summary_lit'] = Variable<bool>(summaryLit);
    }
    if (!nullToAbsent || summaryLitPercent != null) {
      map['summary_lit_percent'] = Variable<int>(summaryLitPercent);
    }
    if (!nullToAbsent || summaryRawResponse != null) {
      map['summary_raw_response'] = Variable<String>(summaryRawResponse);
    }
    if (!nullToAbsent || summaryValid != null) {
      map['summary_valid'] = Variable<bool>(summaryValid);
    }
    if (!nullToAbsent || summarizeCallId != null) {
      map['summarize_call_id'] = Variable<int>(summarizeCallId);
    }
    if (!nullToAbsent || controlStateJson != null) {
      map['control_state_json'] = Variable<String>(controlStateJson);
    }
    if (!nullToAbsent || controlStateUpdatedAt != null) {
      map['control_state_updated_at'] =
          Variable<DateTime>(controlStateUpdatedAt);
    }
    if (!nullToAbsent || evidenceStateJson != null) {
      map['evidence_state_json'] = Variable<String>(evidenceStateJson);
    }
    if (!nullToAbsent || evidenceStateUpdatedAt != null) {
      map['evidence_state_updated_at'] =
          Variable<DateTime>(evidenceStateUpdatedAt);
    }
    if (!nullToAbsent || syncId != null) {
      map['sync_id'] = Variable<String>(syncId);
    }
    if (!nullToAbsent || syncUpdatedAt != null) {
      map['sync_updated_at'] = Variable<DateTime>(syncUpdatedAt);
    }
    if (!nullToAbsent || syncUploadedAt != null) {
      map['sync_uploaded_at'] = Variable<DateTime>(syncUploadedAt);
    }
    return map;
  }

  ChatSessionsCompanion toCompanion(bool nullToAbsent) {
    return ChatSessionsCompanion(
      id: Value(id),
      studentId: Value(studentId),
      courseVersionId: Value(courseVersionId),
      kpKey: Value(kpKey),
      title:
          title == null && nullToAbsent ? const Value.absent() : Value(title),
      startedAt: Value(startedAt),
      endedAt: endedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAt),
      status: Value(status),
      summaryText: summaryText == null && nullToAbsent
          ? const Value.absent()
          : Value(summaryText),
      summaryLit: summaryLit == null && nullToAbsent
          ? const Value.absent()
          : Value(summaryLit),
      summaryLitPercent: summaryLitPercent == null && nullToAbsent
          ? const Value.absent()
          : Value(summaryLitPercent),
      summaryRawResponse: summaryRawResponse == null && nullToAbsent
          ? const Value.absent()
          : Value(summaryRawResponse),
      summaryValid: summaryValid == null && nullToAbsent
          ? const Value.absent()
          : Value(summaryValid),
      summarizeCallId: summarizeCallId == null && nullToAbsent
          ? const Value.absent()
          : Value(summarizeCallId),
      controlStateJson: controlStateJson == null && nullToAbsent
          ? const Value.absent()
          : Value(controlStateJson),
      controlStateUpdatedAt: controlStateUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(controlStateUpdatedAt),
      evidenceStateJson: evidenceStateJson == null && nullToAbsent
          ? const Value.absent()
          : Value(evidenceStateJson),
      evidenceStateUpdatedAt: evidenceStateUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(evidenceStateUpdatedAt),
      syncId:
          syncId == null && nullToAbsent ? const Value.absent() : Value(syncId),
      syncUpdatedAt: syncUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(syncUpdatedAt),
      syncUploadedAt: syncUploadedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(syncUploadedAt),
    );
  }

  factory ChatSession.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatSession(
      id: serializer.fromJson<int>(json['id']),
      studentId: serializer.fromJson<int>(json['studentId']),
      courseVersionId: serializer.fromJson<int>(json['courseVersionId']),
      kpKey: serializer.fromJson<String>(json['kpKey']),
      title: serializer.fromJson<String?>(json['title']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      endedAt: serializer.fromJson<DateTime?>(json['endedAt']),
      status: serializer.fromJson<String>(json['status']),
      summaryText: serializer.fromJson<String?>(json['summaryText']),
      summaryLit: serializer.fromJson<bool?>(json['summaryLit']),
      summaryLitPercent: serializer.fromJson<int?>(json['summaryLitPercent']),
      summaryRawResponse:
          serializer.fromJson<String?>(json['summaryRawResponse']),
      summaryValid: serializer.fromJson<bool?>(json['summaryValid']),
      summarizeCallId: serializer.fromJson<int?>(json['summarizeCallId']),
      controlStateJson: serializer.fromJson<String?>(json['controlStateJson']),
      controlStateUpdatedAt:
          serializer.fromJson<DateTime?>(json['controlStateUpdatedAt']),
      evidenceStateJson:
          serializer.fromJson<String?>(json['evidenceStateJson']),
      evidenceStateUpdatedAt:
          serializer.fromJson<DateTime?>(json['evidenceStateUpdatedAt']),
      syncId: serializer.fromJson<String?>(json['syncId']),
      syncUpdatedAt: serializer.fromJson<DateTime?>(json['syncUpdatedAt']),
      syncUploadedAt: serializer.fromJson<DateTime?>(json['syncUploadedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'studentId': serializer.toJson<int>(studentId),
      'courseVersionId': serializer.toJson<int>(courseVersionId),
      'kpKey': serializer.toJson<String>(kpKey),
      'title': serializer.toJson<String?>(title),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'endedAt': serializer.toJson<DateTime?>(endedAt),
      'status': serializer.toJson<String>(status),
      'summaryText': serializer.toJson<String?>(summaryText),
      'summaryLit': serializer.toJson<bool?>(summaryLit),
      'summaryLitPercent': serializer.toJson<int?>(summaryLitPercent),
      'summaryRawResponse': serializer.toJson<String?>(summaryRawResponse),
      'summaryValid': serializer.toJson<bool?>(summaryValid),
      'summarizeCallId': serializer.toJson<int?>(summarizeCallId),
      'controlStateJson': serializer.toJson<String?>(controlStateJson),
      'controlStateUpdatedAt':
          serializer.toJson<DateTime?>(controlStateUpdatedAt),
      'evidenceStateJson': serializer.toJson<String?>(evidenceStateJson),
      'evidenceStateUpdatedAt':
          serializer.toJson<DateTime?>(evidenceStateUpdatedAt),
      'syncId': serializer.toJson<String?>(syncId),
      'syncUpdatedAt': serializer.toJson<DateTime?>(syncUpdatedAt),
      'syncUploadedAt': serializer.toJson<DateTime?>(syncUploadedAt),
    };
  }

  ChatSession copyWith(
          {int? id,
          int? studentId,
          int? courseVersionId,
          String? kpKey,
          Value<String?> title = const Value.absent(),
          DateTime? startedAt,
          Value<DateTime?> endedAt = const Value.absent(),
          String? status,
          Value<String?> summaryText = const Value.absent(),
          Value<bool?> summaryLit = const Value.absent(),
          Value<int?> summaryLitPercent = const Value.absent(),
          Value<String?> summaryRawResponse = const Value.absent(),
          Value<bool?> summaryValid = const Value.absent(),
          Value<int?> summarizeCallId = const Value.absent(),
          Value<String?> controlStateJson = const Value.absent(),
          Value<DateTime?> controlStateUpdatedAt = const Value.absent(),
          Value<String?> evidenceStateJson = const Value.absent(),
          Value<DateTime?> evidenceStateUpdatedAt = const Value.absent(),
          Value<String?> syncId = const Value.absent(),
          Value<DateTime?> syncUpdatedAt = const Value.absent(),
          Value<DateTime?> syncUploadedAt = const Value.absent()}) =>
      ChatSession(
        id: id ?? this.id,
        studentId: studentId ?? this.studentId,
        courseVersionId: courseVersionId ?? this.courseVersionId,
        kpKey: kpKey ?? this.kpKey,
        title: title.present ? title.value : this.title,
        startedAt: startedAt ?? this.startedAt,
        endedAt: endedAt.present ? endedAt.value : this.endedAt,
        status: status ?? this.status,
        summaryText: summaryText.present ? summaryText.value : this.summaryText,
        summaryLit: summaryLit.present ? summaryLit.value : this.summaryLit,
        summaryLitPercent: summaryLitPercent.present
            ? summaryLitPercent.value
            : this.summaryLitPercent,
        summaryRawResponse: summaryRawResponse.present
            ? summaryRawResponse.value
            : this.summaryRawResponse,
        summaryValid:
            summaryValid.present ? summaryValid.value : this.summaryValid,
        summarizeCallId: summarizeCallId.present
            ? summarizeCallId.value
            : this.summarizeCallId,
        controlStateJson: controlStateJson.present
            ? controlStateJson.value
            : this.controlStateJson,
        controlStateUpdatedAt: controlStateUpdatedAt.present
            ? controlStateUpdatedAt.value
            : this.controlStateUpdatedAt,
        evidenceStateJson: evidenceStateJson.present
            ? evidenceStateJson.value
            : this.evidenceStateJson,
        evidenceStateUpdatedAt: evidenceStateUpdatedAt.present
            ? evidenceStateUpdatedAt.value
            : this.evidenceStateUpdatedAt,
        syncId: syncId.present ? syncId.value : this.syncId,
        syncUpdatedAt:
            syncUpdatedAt.present ? syncUpdatedAt.value : this.syncUpdatedAt,
        syncUploadedAt:
            syncUploadedAt.present ? syncUploadedAt.value : this.syncUploadedAt,
      );
  ChatSession copyWithCompanion(ChatSessionsCompanion data) {
    return ChatSession(
      id: data.id.present ? data.id.value : this.id,
      studentId: data.studentId.present ? data.studentId.value : this.studentId,
      courseVersionId: data.courseVersionId.present
          ? data.courseVersionId.value
          : this.courseVersionId,
      kpKey: data.kpKey.present ? data.kpKey.value : this.kpKey,
      title: data.title.present ? data.title.value : this.title,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
      status: data.status.present ? data.status.value : this.status,
      summaryText:
          data.summaryText.present ? data.summaryText.value : this.summaryText,
      summaryLit:
          data.summaryLit.present ? data.summaryLit.value : this.summaryLit,
      summaryLitPercent: data.summaryLitPercent.present
          ? data.summaryLitPercent.value
          : this.summaryLitPercent,
      summaryRawResponse: data.summaryRawResponse.present
          ? data.summaryRawResponse.value
          : this.summaryRawResponse,
      summaryValid: data.summaryValid.present
          ? data.summaryValid.value
          : this.summaryValid,
      summarizeCallId: data.summarizeCallId.present
          ? data.summarizeCallId.value
          : this.summarizeCallId,
      controlStateJson: data.controlStateJson.present
          ? data.controlStateJson.value
          : this.controlStateJson,
      controlStateUpdatedAt: data.controlStateUpdatedAt.present
          ? data.controlStateUpdatedAt.value
          : this.controlStateUpdatedAt,
      evidenceStateJson: data.evidenceStateJson.present
          ? data.evidenceStateJson.value
          : this.evidenceStateJson,
      evidenceStateUpdatedAt: data.evidenceStateUpdatedAt.present
          ? data.evidenceStateUpdatedAt.value
          : this.evidenceStateUpdatedAt,
      syncId: data.syncId.present ? data.syncId.value : this.syncId,
      syncUpdatedAt: data.syncUpdatedAt.present
          ? data.syncUpdatedAt.value
          : this.syncUpdatedAt,
      syncUploadedAt: data.syncUploadedAt.present
          ? data.syncUploadedAt.value
          : this.syncUploadedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatSession(')
          ..write('id: $id, ')
          ..write('studentId: $studentId, ')
          ..write('courseVersionId: $courseVersionId, ')
          ..write('kpKey: $kpKey, ')
          ..write('title: $title, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('status: $status, ')
          ..write('summaryText: $summaryText, ')
          ..write('summaryLit: $summaryLit, ')
          ..write('summaryLitPercent: $summaryLitPercent, ')
          ..write('summaryRawResponse: $summaryRawResponse, ')
          ..write('summaryValid: $summaryValid, ')
          ..write('summarizeCallId: $summarizeCallId, ')
          ..write('controlStateJson: $controlStateJson, ')
          ..write('controlStateUpdatedAt: $controlStateUpdatedAt, ')
          ..write('evidenceStateJson: $evidenceStateJson, ')
          ..write('evidenceStateUpdatedAt: $evidenceStateUpdatedAt, ')
          ..write('syncId: $syncId, ')
          ..write('syncUpdatedAt: $syncUpdatedAt, ')
          ..write('syncUploadedAt: $syncUploadedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        studentId,
        courseVersionId,
        kpKey,
        title,
        startedAt,
        endedAt,
        status,
        summaryText,
        summaryLit,
        summaryLitPercent,
        summaryRawResponse,
        summaryValid,
        summarizeCallId,
        controlStateJson,
        controlStateUpdatedAt,
        evidenceStateJson,
        evidenceStateUpdatedAt,
        syncId,
        syncUpdatedAt,
        syncUploadedAt
      ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatSession &&
          other.id == this.id &&
          other.studentId == this.studentId &&
          other.courseVersionId == this.courseVersionId &&
          other.kpKey == this.kpKey &&
          other.title == this.title &&
          other.startedAt == this.startedAt &&
          other.endedAt == this.endedAt &&
          other.status == this.status &&
          other.summaryText == this.summaryText &&
          other.summaryLit == this.summaryLit &&
          other.summaryLitPercent == this.summaryLitPercent &&
          other.summaryRawResponse == this.summaryRawResponse &&
          other.summaryValid == this.summaryValid &&
          other.summarizeCallId == this.summarizeCallId &&
          other.controlStateJson == this.controlStateJson &&
          other.controlStateUpdatedAt == this.controlStateUpdatedAt &&
          other.evidenceStateJson == this.evidenceStateJson &&
          other.evidenceStateUpdatedAt == this.evidenceStateUpdatedAt &&
          other.syncId == this.syncId &&
          other.syncUpdatedAt == this.syncUpdatedAt &&
          other.syncUploadedAt == this.syncUploadedAt);
}

class ChatSessionsCompanion extends UpdateCompanion<ChatSession> {
  final Value<int> id;
  final Value<int> studentId;
  final Value<int> courseVersionId;
  final Value<String> kpKey;
  final Value<String?> title;
  final Value<DateTime> startedAt;
  final Value<DateTime?> endedAt;
  final Value<String> status;
  final Value<String?> summaryText;
  final Value<bool?> summaryLit;
  final Value<int?> summaryLitPercent;
  final Value<String?> summaryRawResponse;
  final Value<bool?> summaryValid;
  final Value<int?> summarizeCallId;
  final Value<String?> controlStateJson;
  final Value<DateTime?> controlStateUpdatedAt;
  final Value<String?> evidenceStateJson;
  final Value<DateTime?> evidenceStateUpdatedAt;
  final Value<String?> syncId;
  final Value<DateTime?> syncUpdatedAt;
  final Value<DateTime?> syncUploadedAt;
  const ChatSessionsCompanion({
    this.id = const Value.absent(),
    this.studentId = const Value.absent(),
    this.courseVersionId = const Value.absent(),
    this.kpKey = const Value.absent(),
    this.title = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.status = const Value.absent(),
    this.summaryText = const Value.absent(),
    this.summaryLit = const Value.absent(),
    this.summaryLitPercent = const Value.absent(),
    this.summaryRawResponse = const Value.absent(),
    this.summaryValid = const Value.absent(),
    this.summarizeCallId = const Value.absent(),
    this.controlStateJson = const Value.absent(),
    this.controlStateUpdatedAt = const Value.absent(),
    this.evidenceStateJson = const Value.absent(),
    this.evidenceStateUpdatedAt = const Value.absent(),
    this.syncId = const Value.absent(),
    this.syncUpdatedAt = const Value.absent(),
    this.syncUploadedAt = const Value.absent(),
  });
  ChatSessionsCompanion.insert({
    this.id = const Value.absent(),
    required int studentId,
    required int courseVersionId,
    required String kpKey,
    this.title = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.status = const Value.absent(),
    this.summaryText = const Value.absent(),
    this.summaryLit = const Value.absent(),
    this.summaryLitPercent = const Value.absent(),
    this.summaryRawResponse = const Value.absent(),
    this.summaryValid = const Value.absent(),
    this.summarizeCallId = const Value.absent(),
    this.controlStateJson = const Value.absent(),
    this.controlStateUpdatedAt = const Value.absent(),
    this.evidenceStateJson = const Value.absent(),
    this.evidenceStateUpdatedAt = const Value.absent(),
    this.syncId = const Value.absent(),
    this.syncUpdatedAt = const Value.absent(),
    this.syncUploadedAt = const Value.absent(),
  })  : studentId = Value(studentId),
        courseVersionId = Value(courseVersionId),
        kpKey = Value(kpKey);
  static Insertable<ChatSession> custom({
    Expression<int>? id,
    Expression<int>? studentId,
    Expression<int>? courseVersionId,
    Expression<String>? kpKey,
    Expression<String>? title,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? endedAt,
    Expression<String>? status,
    Expression<String>? summaryText,
    Expression<bool>? summaryLit,
    Expression<int>? summaryLitPercent,
    Expression<String>? summaryRawResponse,
    Expression<bool>? summaryValid,
    Expression<int>? summarizeCallId,
    Expression<String>? controlStateJson,
    Expression<DateTime>? controlStateUpdatedAt,
    Expression<String>? evidenceStateJson,
    Expression<DateTime>? evidenceStateUpdatedAt,
    Expression<String>? syncId,
    Expression<DateTime>? syncUpdatedAt,
    Expression<DateTime>? syncUploadedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (studentId != null) 'student_id': studentId,
      if (courseVersionId != null) 'course_version_id': courseVersionId,
      if (kpKey != null) 'kp_key': kpKey,
      if (title != null) 'title': title,
      if (startedAt != null) 'started_at': startedAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (status != null) 'status': status,
      if (summaryText != null) 'summary_text': summaryText,
      if (summaryLit != null) 'summary_lit': summaryLit,
      if (summaryLitPercent != null) 'summary_lit_percent': summaryLitPercent,
      if (summaryRawResponse != null)
        'summary_raw_response': summaryRawResponse,
      if (summaryValid != null) 'summary_valid': summaryValid,
      if (summarizeCallId != null) 'summarize_call_id': summarizeCallId,
      if (controlStateJson != null) 'control_state_json': controlStateJson,
      if (controlStateUpdatedAt != null)
        'control_state_updated_at': controlStateUpdatedAt,
      if (evidenceStateJson != null) 'evidence_state_json': evidenceStateJson,
      if (evidenceStateUpdatedAt != null)
        'evidence_state_updated_at': evidenceStateUpdatedAt,
      if (syncId != null) 'sync_id': syncId,
      if (syncUpdatedAt != null) 'sync_updated_at': syncUpdatedAt,
      if (syncUploadedAt != null) 'sync_uploaded_at': syncUploadedAt,
    });
  }

  ChatSessionsCompanion copyWith(
      {Value<int>? id,
      Value<int>? studentId,
      Value<int>? courseVersionId,
      Value<String>? kpKey,
      Value<String?>? title,
      Value<DateTime>? startedAt,
      Value<DateTime?>? endedAt,
      Value<String>? status,
      Value<String?>? summaryText,
      Value<bool?>? summaryLit,
      Value<int?>? summaryLitPercent,
      Value<String?>? summaryRawResponse,
      Value<bool?>? summaryValid,
      Value<int?>? summarizeCallId,
      Value<String?>? controlStateJson,
      Value<DateTime?>? controlStateUpdatedAt,
      Value<String?>? evidenceStateJson,
      Value<DateTime?>? evidenceStateUpdatedAt,
      Value<String?>? syncId,
      Value<DateTime?>? syncUpdatedAt,
      Value<DateTime?>? syncUploadedAt}) {
    return ChatSessionsCompanion(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      courseVersionId: courseVersionId ?? this.courseVersionId,
      kpKey: kpKey ?? this.kpKey,
      title: title ?? this.title,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      status: status ?? this.status,
      summaryText: summaryText ?? this.summaryText,
      summaryLit: summaryLit ?? this.summaryLit,
      summaryLitPercent: summaryLitPercent ?? this.summaryLitPercent,
      summaryRawResponse: summaryRawResponse ?? this.summaryRawResponse,
      summaryValid: summaryValid ?? this.summaryValid,
      summarizeCallId: summarizeCallId ?? this.summarizeCallId,
      controlStateJson: controlStateJson ?? this.controlStateJson,
      controlStateUpdatedAt:
          controlStateUpdatedAt ?? this.controlStateUpdatedAt,
      evidenceStateJson: evidenceStateJson ?? this.evidenceStateJson,
      evidenceStateUpdatedAt:
          evidenceStateUpdatedAt ?? this.evidenceStateUpdatedAt,
      syncId: syncId ?? this.syncId,
      syncUpdatedAt: syncUpdatedAt ?? this.syncUpdatedAt,
      syncUploadedAt: syncUploadedAt ?? this.syncUploadedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (studentId.present) {
      map['student_id'] = Variable<int>(studentId.value);
    }
    if (courseVersionId.present) {
      map['course_version_id'] = Variable<int>(courseVersionId.value);
    }
    if (kpKey.present) {
      map['kp_key'] = Variable<String>(kpKey.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<DateTime>(endedAt.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (summaryText.present) {
      map['summary_text'] = Variable<String>(summaryText.value);
    }
    if (summaryLit.present) {
      map['summary_lit'] = Variable<bool>(summaryLit.value);
    }
    if (summaryLitPercent.present) {
      map['summary_lit_percent'] = Variable<int>(summaryLitPercent.value);
    }
    if (summaryRawResponse.present) {
      map['summary_raw_response'] = Variable<String>(summaryRawResponse.value);
    }
    if (summaryValid.present) {
      map['summary_valid'] = Variable<bool>(summaryValid.value);
    }
    if (summarizeCallId.present) {
      map['summarize_call_id'] = Variable<int>(summarizeCallId.value);
    }
    if (controlStateJson.present) {
      map['control_state_json'] = Variable<String>(controlStateJson.value);
    }
    if (controlStateUpdatedAt.present) {
      map['control_state_updated_at'] =
          Variable<DateTime>(controlStateUpdatedAt.value);
    }
    if (evidenceStateJson.present) {
      map['evidence_state_json'] = Variable<String>(evidenceStateJson.value);
    }
    if (evidenceStateUpdatedAt.present) {
      map['evidence_state_updated_at'] =
          Variable<DateTime>(evidenceStateUpdatedAt.value);
    }
    if (syncId.present) {
      map['sync_id'] = Variable<String>(syncId.value);
    }
    if (syncUpdatedAt.present) {
      map['sync_updated_at'] = Variable<DateTime>(syncUpdatedAt.value);
    }
    if (syncUploadedAt.present) {
      map['sync_uploaded_at'] = Variable<DateTime>(syncUploadedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatSessionsCompanion(')
          ..write('id: $id, ')
          ..write('studentId: $studentId, ')
          ..write('courseVersionId: $courseVersionId, ')
          ..write('kpKey: $kpKey, ')
          ..write('title: $title, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('status: $status, ')
          ..write('summaryText: $summaryText, ')
          ..write('summaryLit: $summaryLit, ')
          ..write('summaryLitPercent: $summaryLitPercent, ')
          ..write('summaryRawResponse: $summaryRawResponse, ')
          ..write('summaryValid: $summaryValid, ')
          ..write('summarizeCallId: $summarizeCallId, ')
          ..write('controlStateJson: $controlStateJson, ')
          ..write('controlStateUpdatedAt: $controlStateUpdatedAt, ')
          ..write('evidenceStateJson: $evidenceStateJson, ')
          ..write('evidenceStateUpdatedAt: $evidenceStateUpdatedAt, ')
          ..write('syncId: $syncId, ')
          ..write('syncUpdatedAt: $syncUpdatedAt, ')
          ..write('syncUploadedAt: $syncUploadedAt')
          ..write(')'))
        .toString();
  }
}

class $ChatMessagesTable extends ChatMessages
    with TableInfo<$ChatMessagesTable, ChatMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _sessionIdMeta =
      const VerificationMeta('sessionId');
  @override
  late final GeneratedColumn<int> sessionId = GeneratedColumn<int>(
      'session_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
      'role', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _contentMeta =
      const VerificationMeta('content');
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
      'content', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _rawContentMeta =
      const VerificationMeta('rawContent');
  @override
  late final GeneratedColumn<String> rawContent = GeneratedColumn<String>(
      'raw_content', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _parsedJsonMeta =
      const VerificationMeta('parsedJson');
  @override
  late final GeneratedColumn<String> parsedJson = GeneratedColumn<String>(
      'parsed_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
      'action', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns =>
      [id, sessionId, role, content, rawContent, parsedJson, action, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_messages';
  @override
  VerificationContext validateIntegrity(Insertable<ChatMessage> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('session_id')) {
      context.handle(_sessionIdMeta,
          sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta));
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
          _roleMeta, role.isAcceptableOrUnknown(data['role']!, _roleMeta));
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('content')) {
      context.handle(_contentMeta,
          content.isAcceptableOrUnknown(data['content']!, _contentMeta));
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('raw_content')) {
      context.handle(
          _rawContentMeta,
          rawContent.isAcceptableOrUnknown(
              data['raw_content']!, _rawContentMeta));
    }
    if (data.containsKey('parsed_json')) {
      context.handle(
          _parsedJsonMeta,
          parsedJson.isAcceptableOrUnknown(
              data['parsed_json']!, _parsedJsonMeta));
    }
    if (data.containsKey('action')) {
      context.handle(_actionMeta,
          action.isAcceptableOrUnknown(data['action']!, _actionMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ChatMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatMessage(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      sessionId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}session_id'])!,
      role: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}role'])!,
      content: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content'])!,
      rawContent: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}raw_content']),
      parsedJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}parsed_json']),
      action: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}action']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $ChatMessagesTable createAlias(String alias) {
    return $ChatMessagesTable(attachedDatabase, alias);
  }
}

class ChatMessage extends DataClass implements Insertable<ChatMessage> {
  final int id;
  final int sessionId;
  final String role;
  final String content;
  final String? rawContent;
  final String? parsedJson;
  final String? action;
  final DateTime createdAt;
  const ChatMessage(
      {required this.id,
      required this.sessionId,
      required this.role,
      required this.content,
      this.rawContent,
      this.parsedJson,
      this.action,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['session_id'] = Variable<int>(sessionId);
    map['role'] = Variable<String>(role);
    map['content'] = Variable<String>(content);
    if (!nullToAbsent || rawContent != null) {
      map['raw_content'] = Variable<String>(rawContent);
    }
    if (!nullToAbsent || parsedJson != null) {
      map['parsed_json'] = Variable<String>(parsedJson);
    }
    if (!nullToAbsent || action != null) {
      map['action'] = Variable<String>(action);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ChatMessagesCompanion toCompanion(bool nullToAbsent) {
    return ChatMessagesCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      role: Value(role),
      content: Value(content),
      rawContent: rawContent == null && nullToAbsent
          ? const Value.absent()
          : Value(rawContent),
      parsedJson: parsedJson == null && nullToAbsent
          ? const Value.absent()
          : Value(parsedJson),
      action:
          action == null && nullToAbsent ? const Value.absent() : Value(action),
      createdAt: Value(createdAt),
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatMessage(
      id: serializer.fromJson<int>(json['id']),
      sessionId: serializer.fromJson<int>(json['sessionId']),
      role: serializer.fromJson<String>(json['role']),
      content: serializer.fromJson<String>(json['content']),
      rawContent: serializer.fromJson<String?>(json['rawContent']),
      parsedJson: serializer.fromJson<String?>(json['parsedJson']),
      action: serializer.fromJson<String?>(json['action']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sessionId': serializer.toJson<int>(sessionId),
      'role': serializer.toJson<String>(role),
      'content': serializer.toJson<String>(content),
      'rawContent': serializer.toJson<String?>(rawContent),
      'parsedJson': serializer.toJson<String?>(parsedJson),
      'action': serializer.toJson<String?>(action),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ChatMessage copyWith(
          {int? id,
          int? sessionId,
          String? role,
          String? content,
          Value<String?> rawContent = const Value.absent(),
          Value<String?> parsedJson = const Value.absent(),
          Value<String?> action = const Value.absent(),
          DateTime? createdAt}) =>
      ChatMessage(
        id: id ?? this.id,
        sessionId: sessionId ?? this.sessionId,
        role: role ?? this.role,
        content: content ?? this.content,
        rawContent: rawContent.present ? rawContent.value : this.rawContent,
        parsedJson: parsedJson.present ? parsedJson.value : this.parsedJson,
        action: action.present ? action.value : this.action,
        createdAt: createdAt ?? this.createdAt,
      );
  ChatMessage copyWithCompanion(ChatMessagesCompanion data) {
    return ChatMessage(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      role: data.role.present ? data.role.value : this.role,
      content: data.content.present ? data.content.value : this.content,
      rawContent:
          data.rawContent.present ? data.rawContent.value : this.rawContent,
      parsedJson:
          data.parsedJson.present ? data.parsedJson.value : this.parsedJson,
      action: data.action.present ? data.action.value : this.action,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatMessage(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('rawContent: $rawContent, ')
          ..write('parsedJson: $parsedJson, ')
          ..write('action: $action, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, sessionId, role, content, rawContent, parsedJson, action, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatMessage &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.role == this.role &&
          other.content == this.content &&
          other.rawContent == this.rawContent &&
          other.parsedJson == this.parsedJson &&
          other.action == this.action &&
          other.createdAt == this.createdAt);
}

class ChatMessagesCompanion extends UpdateCompanion<ChatMessage> {
  final Value<int> id;
  final Value<int> sessionId;
  final Value<String> role;
  final Value<String> content;
  final Value<String?> rawContent;
  final Value<String?> parsedJson;
  final Value<String?> action;
  final Value<DateTime> createdAt;
  const ChatMessagesCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.role = const Value.absent(),
    this.content = const Value.absent(),
    this.rawContent = const Value.absent(),
    this.parsedJson = const Value.absent(),
    this.action = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  ChatMessagesCompanion.insert({
    this.id = const Value.absent(),
    required int sessionId,
    required String role,
    required String content,
    this.rawContent = const Value.absent(),
    this.parsedJson = const Value.absent(),
    this.action = const Value.absent(),
    this.createdAt = const Value.absent(),
  })  : sessionId = Value(sessionId),
        role = Value(role),
        content = Value(content);
  static Insertable<ChatMessage> custom({
    Expression<int>? id,
    Expression<int>? sessionId,
    Expression<String>? role,
    Expression<String>? content,
    Expression<String>? rawContent,
    Expression<String>? parsedJson,
    Expression<String>? action,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (role != null) 'role': role,
      if (content != null) 'content': content,
      if (rawContent != null) 'raw_content': rawContent,
      if (parsedJson != null) 'parsed_json': parsedJson,
      if (action != null) 'action': action,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  ChatMessagesCompanion copyWith(
      {Value<int>? id,
      Value<int>? sessionId,
      Value<String>? role,
      Value<String>? content,
      Value<String?>? rawContent,
      Value<String?>? parsedJson,
      Value<String?>? action,
      Value<DateTime>? createdAt}) {
    return ChatMessagesCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      role: role ?? this.role,
      content: content ?? this.content,
      rawContent: rawContent ?? this.rawContent,
      parsedJson: parsedJson ?? this.parsedJson,
      action: action ?? this.action,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<int>(sessionId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (rawContent.present) {
      map['raw_content'] = Variable<String>(rawContent.value);
    }
    if (parsedJson.present) {
      map['parsed_json'] = Variable<String>(parsedJson.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatMessagesCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('rawContent: $rawContent, ')
          ..write('parsedJson: $parsedJson, ')
          ..write('action: $action, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $LlmCallsTable extends LlmCalls with TableInfo<$LlmCallsTable, LlmCall> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LlmCallsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _callHashMeta =
      const VerificationMeta('callHash');
  @override
  late final GeneratedColumn<String> callHash = GeneratedColumn<String>(
      'call_hash', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _promptNameMeta =
      const VerificationMeta('promptName');
  @override
  late final GeneratedColumn<String> promptName = GeneratedColumn<String>(
      'prompt_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _renderedPromptMeta =
      const VerificationMeta('renderedPrompt');
  @override
  late final GeneratedColumn<String> renderedPrompt = GeneratedColumn<String>(
      'rendered_prompt', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
      'model', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _baseUrlMeta =
      const VerificationMeta('baseUrl');
  @override
  late final GeneratedColumn<String> baseUrl = GeneratedColumn<String>(
      'base_url', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _responseTextMeta =
      const VerificationMeta('responseText');
  @override
  late final GeneratedColumn<String> responseText = GeneratedColumn<String>(
      'response_text', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _responseJsonMeta =
      const VerificationMeta('responseJson');
  @override
  late final GeneratedColumn<String> responseJson = GeneratedColumn<String>(
      'response_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _parseValidMeta =
      const VerificationMeta('parseValid');
  @override
  late final GeneratedColumn<bool> parseValid = GeneratedColumn<bool>(
      'parse_valid', aliasedName, true,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("parse_valid" IN (0, 1))'));
  static const VerificationMeta _parseErrorMeta =
      const VerificationMeta('parseError');
  @override
  late final GeneratedColumn<String> parseError = GeneratedColumn<String>(
      'parse_error', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _latencyMsMeta =
      const VerificationMeta('latencyMs');
  @override
  late final GeneratedColumn<int> latencyMs = GeneratedColumn<int>(
      'latency_ms', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _teacherIdMeta =
      const VerificationMeta('teacherId');
  @override
  late final GeneratedColumn<int> teacherId = GeneratedColumn<int>(
      'teacher_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _studentIdMeta =
      const VerificationMeta('studentId');
  @override
  late final GeneratedColumn<int> studentId = GeneratedColumn<int>(
      'student_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _courseVersionIdMeta =
      const VerificationMeta('courseVersionId');
  @override
  late final GeneratedColumn<int> courseVersionId = GeneratedColumn<int>(
      'course_version_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _sessionIdMeta =
      const VerificationMeta('sessionId');
  @override
  late final GeneratedColumn<int> sessionId = GeneratedColumn<int>(
      'session_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _kpKeyMeta = const VerificationMeta('kpKey');
  @override
  late final GeneratedColumn<String> kpKey = GeneratedColumn<String>(
      'kp_key', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
      'action', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
      'mode', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        callHash,
        promptName,
        renderedPrompt,
        model,
        baseUrl,
        responseText,
        responseJson,
        parseValid,
        parseError,
        latencyMs,
        teacherId,
        studentId,
        courseVersionId,
        sessionId,
        kpKey,
        action,
        createdAt,
        mode
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'llm_calls';
  @override
  VerificationContext validateIntegrity(Insertable<LlmCall> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('call_hash')) {
      context.handle(_callHashMeta,
          callHash.isAcceptableOrUnknown(data['call_hash']!, _callHashMeta));
    } else if (isInserting) {
      context.missing(_callHashMeta);
    }
    if (data.containsKey('prompt_name')) {
      context.handle(
          _promptNameMeta,
          promptName.isAcceptableOrUnknown(
              data['prompt_name']!, _promptNameMeta));
    } else if (isInserting) {
      context.missing(_promptNameMeta);
    }
    if (data.containsKey('rendered_prompt')) {
      context.handle(
          _renderedPromptMeta,
          renderedPrompt.isAcceptableOrUnknown(
              data['rendered_prompt']!, _renderedPromptMeta));
    } else if (isInserting) {
      context.missing(_renderedPromptMeta);
    }
    if (data.containsKey('model')) {
      context.handle(
          _modelMeta, model.isAcceptableOrUnknown(data['model']!, _modelMeta));
    } else if (isInserting) {
      context.missing(_modelMeta);
    }
    if (data.containsKey('base_url')) {
      context.handle(_baseUrlMeta,
          baseUrl.isAcceptableOrUnknown(data['base_url']!, _baseUrlMeta));
    } else if (isInserting) {
      context.missing(_baseUrlMeta);
    }
    if (data.containsKey('response_text')) {
      context.handle(
          _responseTextMeta,
          responseText.isAcceptableOrUnknown(
              data['response_text']!, _responseTextMeta));
    }
    if (data.containsKey('response_json')) {
      context.handle(
          _responseJsonMeta,
          responseJson.isAcceptableOrUnknown(
              data['response_json']!, _responseJsonMeta));
    }
    if (data.containsKey('parse_valid')) {
      context.handle(
          _parseValidMeta,
          parseValid.isAcceptableOrUnknown(
              data['parse_valid']!, _parseValidMeta));
    }
    if (data.containsKey('parse_error')) {
      context.handle(
          _parseErrorMeta,
          parseError.isAcceptableOrUnknown(
              data['parse_error']!, _parseErrorMeta));
    }
    if (data.containsKey('latency_ms')) {
      context.handle(_latencyMsMeta,
          latencyMs.isAcceptableOrUnknown(data['latency_ms']!, _latencyMsMeta));
    }
    if (data.containsKey('teacher_id')) {
      context.handle(_teacherIdMeta,
          teacherId.isAcceptableOrUnknown(data['teacher_id']!, _teacherIdMeta));
    }
    if (data.containsKey('student_id')) {
      context.handle(_studentIdMeta,
          studentId.isAcceptableOrUnknown(data['student_id']!, _studentIdMeta));
    }
    if (data.containsKey('course_version_id')) {
      context.handle(
          _courseVersionIdMeta,
          courseVersionId.isAcceptableOrUnknown(
              data['course_version_id']!, _courseVersionIdMeta));
    }
    if (data.containsKey('session_id')) {
      context.handle(_sessionIdMeta,
          sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta));
    }
    if (data.containsKey('kp_key')) {
      context.handle(
          _kpKeyMeta, kpKey.isAcceptableOrUnknown(data['kp_key']!, _kpKeyMeta));
    }
    if (data.containsKey('action')) {
      context.handle(_actionMeta,
          action.isAcceptableOrUnknown(data['action']!, _actionMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('mode')) {
      context.handle(
          _modeMeta, mode.isAcceptableOrUnknown(data['mode']!, _modeMeta));
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
        {callHash},
      ];
  @override
  LlmCall map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LlmCall(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      callHash: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}call_hash'])!,
      promptName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}prompt_name'])!,
      renderedPrompt: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}rendered_prompt'])!,
      model: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}model'])!,
      baseUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}base_url'])!,
      responseText: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}response_text']),
      responseJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}response_json']),
      parseValid: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}parse_valid']),
      parseError: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}parse_error']),
      latencyMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}latency_ms']),
      teacherId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}teacher_id']),
      studentId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}student_id']),
      courseVersionId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}course_version_id']),
      sessionId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}session_id']),
      kpKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}kp_key']),
      action: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}action']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      mode: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}mode'])!,
    );
  }

  @override
  $LlmCallsTable createAlias(String alias) {
    return $LlmCallsTable(attachedDatabase, alias);
  }
}

class LlmCall extends DataClass implements Insertable<LlmCall> {
  final int id;
  final String callHash;
  final String promptName;
  final String renderedPrompt;
  final String model;
  final String baseUrl;
  final String? responseText;
  final String? responseJson;
  final bool? parseValid;
  final String? parseError;
  final int? latencyMs;
  final int? teacherId;
  final int? studentId;
  final int? courseVersionId;
  final int? sessionId;
  final String? kpKey;
  final String? action;
  final DateTime createdAt;
  final String mode;
  const LlmCall(
      {required this.id,
      required this.callHash,
      required this.promptName,
      required this.renderedPrompt,
      required this.model,
      required this.baseUrl,
      this.responseText,
      this.responseJson,
      this.parseValid,
      this.parseError,
      this.latencyMs,
      this.teacherId,
      this.studentId,
      this.courseVersionId,
      this.sessionId,
      this.kpKey,
      this.action,
      required this.createdAt,
      required this.mode});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['call_hash'] = Variable<String>(callHash);
    map['prompt_name'] = Variable<String>(promptName);
    map['rendered_prompt'] = Variable<String>(renderedPrompt);
    map['model'] = Variable<String>(model);
    map['base_url'] = Variable<String>(baseUrl);
    if (!nullToAbsent || responseText != null) {
      map['response_text'] = Variable<String>(responseText);
    }
    if (!nullToAbsent || responseJson != null) {
      map['response_json'] = Variable<String>(responseJson);
    }
    if (!nullToAbsent || parseValid != null) {
      map['parse_valid'] = Variable<bool>(parseValid);
    }
    if (!nullToAbsent || parseError != null) {
      map['parse_error'] = Variable<String>(parseError);
    }
    if (!nullToAbsent || latencyMs != null) {
      map['latency_ms'] = Variable<int>(latencyMs);
    }
    if (!nullToAbsent || teacherId != null) {
      map['teacher_id'] = Variable<int>(teacherId);
    }
    if (!nullToAbsent || studentId != null) {
      map['student_id'] = Variable<int>(studentId);
    }
    if (!nullToAbsent || courseVersionId != null) {
      map['course_version_id'] = Variable<int>(courseVersionId);
    }
    if (!nullToAbsent || sessionId != null) {
      map['session_id'] = Variable<int>(sessionId);
    }
    if (!nullToAbsent || kpKey != null) {
      map['kp_key'] = Variable<String>(kpKey);
    }
    if (!nullToAbsent || action != null) {
      map['action'] = Variable<String>(action);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['mode'] = Variable<String>(mode);
    return map;
  }

  LlmCallsCompanion toCompanion(bool nullToAbsent) {
    return LlmCallsCompanion(
      id: Value(id),
      callHash: Value(callHash),
      promptName: Value(promptName),
      renderedPrompt: Value(renderedPrompt),
      model: Value(model),
      baseUrl: Value(baseUrl),
      responseText: responseText == null && nullToAbsent
          ? const Value.absent()
          : Value(responseText),
      responseJson: responseJson == null && nullToAbsent
          ? const Value.absent()
          : Value(responseJson),
      parseValid: parseValid == null && nullToAbsent
          ? const Value.absent()
          : Value(parseValid),
      parseError: parseError == null && nullToAbsent
          ? const Value.absent()
          : Value(parseError),
      latencyMs: latencyMs == null && nullToAbsent
          ? const Value.absent()
          : Value(latencyMs),
      teacherId: teacherId == null && nullToAbsent
          ? const Value.absent()
          : Value(teacherId),
      studentId: studentId == null && nullToAbsent
          ? const Value.absent()
          : Value(studentId),
      courseVersionId: courseVersionId == null && nullToAbsent
          ? const Value.absent()
          : Value(courseVersionId),
      sessionId: sessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionId),
      kpKey:
          kpKey == null && nullToAbsent ? const Value.absent() : Value(kpKey),
      action:
          action == null && nullToAbsent ? const Value.absent() : Value(action),
      createdAt: Value(createdAt),
      mode: Value(mode),
    );
  }

  factory LlmCall.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LlmCall(
      id: serializer.fromJson<int>(json['id']),
      callHash: serializer.fromJson<String>(json['callHash']),
      promptName: serializer.fromJson<String>(json['promptName']),
      renderedPrompt: serializer.fromJson<String>(json['renderedPrompt']),
      model: serializer.fromJson<String>(json['model']),
      baseUrl: serializer.fromJson<String>(json['baseUrl']),
      responseText: serializer.fromJson<String?>(json['responseText']),
      responseJson: serializer.fromJson<String?>(json['responseJson']),
      parseValid: serializer.fromJson<bool?>(json['parseValid']),
      parseError: serializer.fromJson<String?>(json['parseError']),
      latencyMs: serializer.fromJson<int?>(json['latencyMs']),
      teacherId: serializer.fromJson<int?>(json['teacherId']),
      studentId: serializer.fromJson<int?>(json['studentId']),
      courseVersionId: serializer.fromJson<int?>(json['courseVersionId']),
      sessionId: serializer.fromJson<int?>(json['sessionId']),
      kpKey: serializer.fromJson<String?>(json['kpKey']),
      action: serializer.fromJson<String?>(json['action']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      mode: serializer.fromJson<String>(json['mode']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'callHash': serializer.toJson<String>(callHash),
      'promptName': serializer.toJson<String>(promptName),
      'renderedPrompt': serializer.toJson<String>(renderedPrompt),
      'model': serializer.toJson<String>(model),
      'baseUrl': serializer.toJson<String>(baseUrl),
      'responseText': serializer.toJson<String?>(responseText),
      'responseJson': serializer.toJson<String?>(responseJson),
      'parseValid': serializer.toJson<bool?>(parseValid),
      'parseError': serializer.toJson<String?>(parseError),
      'latencyMs': serializer.toJson<int?>(latencyMs),
      'teacherId': serializer.toJson<int?>(teacherId),
      'studentId': serializer.toJson<int?>(studentId),
      'courseVersionId': serializer.toJson<int?>(courseVersionId),
      'sessionId': serializer.toJson<int?>(sessionId),
      'kpKey': serializer.toJson<String?>(kpKey),
      'action': serializer.toJson<String?>(action),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'mode': serializer.toJson<String>(mode),
    };
  }

  LlmCall copyWith(
          {int? id,
          String? callHash,
          String? promptName,
          String? renderedPrompt,
          String? model,
          String? baseUrl,
          Value<String?> responseText = const Value.absent(),
          Value<String?> responseJson = const Value.absent(),
          Value<bool?> parseValid = const Value.absent(),
          Value<String?> parseError = const Value.absent(),
          Value<int?> latencyMs = const Value.absent(),
          Value<int?> teacherId = const Value.absent(),
          Value<int?> studentId = const Value.absent(),
          Value<int?> courseVersionId = const Value.absent(),
          Value<int?> sessionId = const Value.absent(),
          Value<String?> kpKey = const Value.absent(),
          Value<String?> action = const Value.absent(),
          DateTime? createdAt,
          String? mode}) =>
      LlmCall(
        id: id ?? this.id,
        callHash: callHash ?? this.callHash,
        promptName: promptName ?? this.promptName,
        renderedPrompt: renderedPrompt ?? this.renderedPrompt,
        model: model ?? this.model,
        baseUrl: baseUrl ?? this.baseUrl,
        responseText:
            responseText.present ? responseText.value : this.responseText,
        responseJson:
            responseJson.present ? responseJson.value : this.responseJson,
        parseValid: parseValid.present ? parseValid.value : this.parseValid,
        parseError: parseError.present ? parseError.value : this.parseError,
        latencyMs: latencyMs.present ? latencyMs.value : this.latencyMs,
        teacherId: teacherId.present ? teacherId.value : this.teacherId,
        studentId: studentId.present ? studentId.value : this.studentId,
        courseVersionId: courseVersionId.present
            ? courseVersionId.value
            : this.courseVersionId,
        sessionId: sessionId.present ? sessionId.value : this.sessionId,
        kpKey: kpKey.present ? kpKey.value : this.kpKey,
        action: action.present ? action.value : this.action,
        createdAt: createdAt ?? this.createdAt,
        mode: mode ?? this.mode,
      );
  LlmCall copyWithCompanion(LlmCallsCompanion data) {
    return LlmCall(
      id: data.id.present ? data.id.value : this.id,
      callHash: data.callHash.present ? data.callHash.value : this.callHash,
      promptName:
          data.promptName.present ? data.promptName.value : this.promptName,
      renderedPrompt: data.renderedPrompt.present
          ? data.renderedPrompt.value
          : this.renderedPrompt,
      model: data.model.present ? data.model.value : this.model,
      baseUrl: data.baseUrl.present ? data.baseUrl.value : this.baseUrl,
      responseText: data.responseText.present
          ? data.responseText.value
          : this.responseText,
      responseJson: data.responseJson.present
          ? data.responseJson.value
          : this.responseJson,
      parseValid:
          data.parseValid.present ? data.parseValid.value : this.parseValid,
      parseError:
          data.parseError.present ? data.parseError.value : this.parseError,
      latencyMs: data.latencyMs.present ? data.latencyMs.value : this.latencyMs,
      teacherId: data.teacherId.present ? data.teacherId.value : this.teacherId,
      studentId: data.studentId.present ? data.studentId.value : this.studentId,
      courseVersionId: data.courseVersionId.present
          ? data.courseVersionId.value
          : this.courseVersionId,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      kpKey: data.kpKey.present ? data.kpKey.value : this.kpKey,
      action: data.action.present ? data.action.value : this.action,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      mode: data.mode.present ? data.mode.value : this.mode,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LlmCall(')
          ..write('id: $id, ')
          ..write('callHash: $callHash, ')
          ..write('promptName: $promptName, ')
          ..write('renderedPrompt: $renderedPrompt, ')
          ..write('model: $model, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('responseText: $responseText, ')
          ..write('responseJson: $responseJson, ')
          ..write('parseValid: $parseValid, ')
          ..write('parseError: $parseError, ')
          ..write('latencyMs: $latencyMs, ')
          ..write('teacherId: $teacherId, ')
          ..write('studentId: $studentId, ')
          ..write('courseVersionId: $courseVersionId, ')
          ..write('sessionId: $sessionId, ')
          ..write('kpKey: $kpKey, ')
          ..write('action: $action, ')
          ..write('createdAt: $createdAt, ')
          ..write('mode: $mode')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      callHash,
      promptName,
      renderedPrompt,
      model,
      baseUrl,
      responseText,
      responseJson,
      parseValid,
      parseError,
      latencyMs,
      teacherId,
      studentId,
      courseVersionId,
      sessionId,
      kpKey,
      action,
      createdAt,
      mode);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LlmCall &&
          other.id == this.id &&
          other.callHash == this.callHash &&
          other.promptName == this.promptName &&
          other.renderedPrompt == this.renderedPrompt &&
          other.model == this.model &&
          other.baseUrl == this.baseUrl &&
          other.responseText == this.responseText &&
          other.responseJson == this.responseJson &&
          other.parseValid == this.parseValid &&
          other.parseError == this.parseError &&
          other.latencyMs == this.latencyMs &&
          other.teacherId == this.teacherId &&
          other.studentId == this.studentId &&
          other.courseVersionId == this.courseVersionId &&
          other.sessionId == this.sessionId &&
          other.kpKey == this.kpKey &&
          other.action == this.action &&
          other.createdAt == this.createdAt &&
          other.mode == this.mode);
}

class LlmCallsCompanion extends UpdateCompanion<LlmCall> {
  final Value<int> id;
  final Value<String> callHash;
  final Value<String> promptName;
  final Value<String> renderedPrompt;
  final Value<String> model;
  final Value<String> baseUrl;
  final Value<String?> responseText;
  final Value<String?> responseJson;
  final Value<bool?> parseValid;
  final Value<String?> parseError;
  final Value<int?> latencyMs;
  final Value<int?> teacherId;
  final Value<int?> studentId;
  final Value<int?> courseVersionId;
  final Value<int?> sessionId;
  final Value<String?> kpKey;
  final Value<String?> action;
  final Value<DateTime> createdAt;
  final Value<String> mode;
  const LlmCallsCompanion({
    this.id = const Value.absent(),
    this.callHash = const Value.absent(),
    this.promptName = const Value.absent(),
    this.renderedPrompt = const Value.absent(),
    this.model = const Value.absent(),
    this.baseUrl = const Value.absent(),
    this.responseText = const Value.absent(),
    this.responseJson = const Value.absent(),
    this.parseValid = const Value.absent(),
    this.parseError = const Value.absent(),
    this.latencyMs = const Value.absent(),
    this.teacherId = const Value.absent(),
    this.studentId = const Value.absent(),
    this.courseVersionId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.kpKey = const Value.absent(),
    this.action = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.mode = const Value.absent(),
  });
  LlmCallsCompanion.insert({
    this.id = const Value.absent(),
    required String callHash,
    required String promptName,
    required String renderedPrompt,
    required String model,
    required String baseUrl,
    this.responseText = const Value.absent(),
    this.responseJson = const Value.absent(),
    this.parseValid = const Value.absent(),
    this.parseError = const Value.absent(),
    this.latencyMs = const Value.absent(),
    this.teacherId = const Value.absent(),
    this.studentId = const Value.absent(),
    this.courseVersionId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.kpKey = const Value.absent(),
    this.action = const Value.absent(),
    this.createdAt = const Value.absent(),
    required String mode,
  })  : callHash = Value(callHash),
        promptName = Value(promptName),
        renderedPrompt = Value(renderedPrompt),
        model = Value(model),
        baseUrl = Value(baseUrl),
        mode = Value(mode);
  static Insertable<LlmCall> custom({
    Expression<int>? id,
    Expression<String>? callHash,
    Expression<String>? promptName,
    Expression<String>? renderedPrompt,
    Expression<String>? model,
    Expression<String>? baseUrl,
    Expression<String>? responseText,
    Expression<String>? responseJson,
    Expression<bool>? parseValid,
    Expression<String>? parseError,
    Expression<int>? latencyMs,
    Expression<int>? teacherId,
    Expression<int>? studentId,
    Expression<int>? courseVersionId,
    Expression<int>? sessionId,
    Expression<String>? kpKey,
    Expression<String>? action,
    Expression<DateTime>? createdAt,
    Expression<String>? mode,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (callHash != null) 'call_hash': callHash,
      if (promptName != null) 'prompt_name': promptName,
      if (renderedPrompt != null) 'rendered_prompt': renderedPrompt,
      if (model != null) 'model': model,
      if (baseUrl != null) 'base_url': baseUrl,
      if (responseText != null) 'response_text': responseText,
      if (responseJson != null) 'response_json': responseJson,
      if (parseValid != null) 'parse_valid': parseValid,
      if (parseError != null) 'parse_error': parseError,
      if (latencyMs != null) 'latency_ms': latencyMs,
      if (teacherId != null) 'teacher_id': teacherId,
      if (studentId != null) 'student_id': studentId,
      if (courseVersionId != null) 'course_version_id': courseVersionId,
      if (sessionId != null) 'session_id': sessionId,
      if (kpKey != null) 'kp_key': kpKey,
      if (action != null) 'action': action,
      if (createdAt != null) 'created_at': createdAt,
      if (mode != null) 'mode': mode,
    });
  }

  LlmCallsCompanion copyWith(
      {Value<int>? id,
      Value<String>? callHash,
      Value<String>? promptName,
      Value<String>? renderedPrompt,
      Value<String>? model,
      Value<String>? baseUrl,
      Value<String?>? responseText,
      Value<String?>? responseJson,
      Value<bool?>? parseValid,
      Value<String?>? parseError,
      Value<int?>? latencyMs,
      Value<int?>? teacherId,
      Value<int?>? studentId,
      Value<int?>? courseVersionId,
      Value<int?>? sessionId,
      Value<String?>? kpKey,
      Value<String?>? action,
      Value<DateTime>? createdAt,
      Value<String>? mode}) {
    return LlmCallsCompanion(
      id: id ?? this.id,
      callHash: callHash ?? this.callHash,
      promptName: promptName ?? this.promptName,
      renderedPrompt: renderedPrompt ?? this.renderedPrompt,
      model: model ?? this.model,
      baseUrl: baseUrl ?? this.baseUrl,
      responseText: responseText ?? this.responseText,
      responseJson: responseJson ?? this.responseJson,
      parseValid: parseValid ?? this.parseValid,
      parseError: parseError ?? this.parseError,
      latencyMs: latencyMs ?? this.latencyMs,
      teacherId: teacherId ?? this.teacherId,
      studentId: studentId ?? this.studentId,
      courseVersionId: courseVersionId ?? this.courseVersionId,
      sessionId: sessionId ?? this.sessionId,
      kpKey: kpKey ?? this.kpKey,
      action: action ?? this.action,
      createdAt: createdAt ?? this.createdAt,
      mode: mode ?? this.mode,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (callHash.present) {
      map['call_hash'] = Variable<String>(callHash.value);
    }
    if (promptName.present) {
      map['prompt_name'] = Variable<String>(promptName.value);
    }
    if (renderedPrompt.present) {
      map['rendered_prompt'] = Variable<String>(renderedPrompt.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (baseUrl.present) {
      map['base_url'] = Variable<String>(baseUrl.value);
    }
    if (responseText.present) {
      map['response_text'] = Variable<String>(responseText.value);
    }
    if (responseJson.present) {
      map['response_json'] = Variable<String>(responseJson.value);
    }
    if (parseValid.present) {
      map['parse_valid'] = Variable<bool>(parseValid.value);
    }
    if (parseError.present) {
      map['parse_error'] = Variable<String>(parseError.value);
    }
    if (latencyMs.present) {
      map['latency_ms'] = Variable<int>(latencyMs.value);
    }
    if (teacherId.present) {
      map['teacher_id'] = Variable<int>(teacherId.value);
    }
    if (studentId.present) {
      map['student_id'] = Variable<int>(studentId.value);
    }
    if (courseVersionId.present) {
      map['course_version_id'] = Variable<int>(courseVersionId.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<int>(sessionId.value);
    }
    if (kpKey.present) {
      map['kp_key'] = Variable<String>(kpKey.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LlmCallsCompanion(')
          ..write('id: $id, ')
          ..write('callHash: $callHash, ')
          ..write('promptName: $promptName, ')
          ..write('renderedPrompt: $renderedPrompt, ')
          ..write('model: $model, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('responseText: $responseText, ')
          ..write('responseJson: $responseJson, ')
          ..write('parseValid: $parseValid, ')
          ..write('parseError: $parseError, ')
          ..write('latencyMs: $latencyMs, ')
          ..write('teacherId: $teacherId, ')
          ..write('studentId: $studentId, ')
          ..write('courseVersionId: $courseVersionId, ')
          ..write('sessionId: $sessionId, ')
          ..write('kpKey: $kpKey, ')
          ..write('action: $action, ')
          ..write('createdAt: $createdAt, ')
          ..write('mode: $mode')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _baseUrlMeta =
      const VerificationMeta('baseUrl');
  @override
  late final GeneratedColumn<String> baseUrl = GeneratedColumn<String>(
      'base_url', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _providerIdMeta =
      const VerificationMeta('providerId');
  @override
  late final GeneratedColumn<String> providerId = GeneratedColumn<String>(
      'provider_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
      'model', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _reasoningEffortMeta =
      const VerificationMeta('reasoningEffort');
  @override
  late final GeneratedColumn<String> reasoningEffort = GeneratedColumn<String>(
      'reasoning_effort', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('medium'));
  static const VerificationMeta _ttsModelMeta =
      const VerificationMeta('ttsModel');
  @override
  late final GeneratedColumn<String> ttsModel = GeneratedColumn<String>(
      'tts_model', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _sttModelMeta =
      const VerificationMeta('sttModel');
  @override
  late final GeneratedColumn<String> sttModel = GeneratedColumn<String>(
      'stt_model', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _timeoutSecondsMeta =
      const VerificationMeta('timeoutSeconds');
  @override
  late final GeneratedColumn<int> timeoutSeconds = GeneratedColumn<int>(
      'timeout_seconds', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _maxTokensMeta =
      const VerificationMeta('maxTokens');
  @override
  late final GeneratedColumn<int> maxTokens = GeneratedColumn<int>(
      'max_tokens', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _ttsInitialDelayMsMeta =
      const VerificationMeta('ttsInitialDelayMs');
  @override
  late final GeneratedColumn<int> ttsInitialDelayMs = GeneratedColumn<int>(
      'tts_initial_delay_ms', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(60000));
  static const VerificationMeta _ttsTextLeadMsMeta =
      const VerificationMeta('ttsTextLeadMs');
  @override
  late final GeneratedColumn<int> ttsTextLeadMs = GeneratedColumn<int>(
      'tts_text_lead_ms', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1000));
  static const VerificationMeta _ttsAudioPathMeta =
      const VerificationMeta('ttsAudioPath');
  @override
  late final GeneratedColumn<String> ttsAudioPath = GeneratedColumn<String>(
      'tts_audio_path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _sttAutoSendMeta =
      const VerificationMeta('sttAutoSend');
  @override
  late final GeneratedColumn<bool> sttAutoSend = GeneratedColumn<bool>(
      'stt_auto_send', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("stt_auto_send" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _enterToSendMeta =
      const VerificationMeta('enterToSend');
  @override
  late final GeneratedColumn<bool> enterToSend = GeneratedColumn<bool>(
      'enter_to_send', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("enter_to_send" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _studyModeEnabledMeta =
      const VerificationMeta('studyModeEnabled');
  @override
  late final GeneratedColumn<bool> studyModeEnabled = GeneratedColumn<bool>(
      'study_mode_enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("study_mode_enabled" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _logDirectoryMeta =
      const VerificationMeta('logDirectory');
  @override
  late final GeneratedColumn<String> logDirectory = GeneratedColumn<String>(
      'log_directory', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _llmLogPathMeta =
      const VerificationMeta('llmLogPath');
  @override
  late final GeneratedColumn<String> llmLogPath = GeneratedColumn<String>(
      'llm_log_path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _ttsLogPathMeta =
      const VerificationMeta('ttsLogPath');
  @override
  late final GeneratedColumn<String> ttsLogPath = GeneratedColumn<String>(
      'tts_log_path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _llmModeMeta =
      const VerificationMeta('llmMode');
  @override
  late final GeneratedColumn<String> llmMode = GeneratedColumn<String>(
      'llm_mode', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _localeMeta = const VerificationMeta('locale');
  @override
  late final GeneratedColumn<String> locale = GeneratedColumn<String>(
      'locale', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        baseUrl,
        providerId,
        model,
        reasoningEffort,
        ttsModel,
        sttModel,
        timeoutSeconds,
        maxTokens,
        ttsInitialDelayMs,
        ttsTextLeadMs,
        ttsAudioPath,
        sttAutoSend,
        enterToSend,
        studyModeEnabled,
        logDirectory,
        llmLogPath,
        ttsLogPath,
        llmMode,
        locale,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(Insertable<AppSetting> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('base_url')) {
      context.handle(_baseUrlMeta,
          baseUrl.isAcceptableOrUnknown(data['base_url']!, _baseUrlMeta));
    } else if (isInserting) {
      context.missing(_baseUrlMeta);
    }
    if (data.containsKey('provider_id')) {
      context.handle(
          _providerIdMeta,
          providerId.isAcceptableOrUnknown(
              data['provider_id']!, _providerIdMeta));
    }
    if (data.containsKey('model')) {
      context.handle(
          _modelMeta, model.isAcceptableOrUnknown(data['model']!, _modelMeta));
    } else if (isInserting) {
      context.missing(_modelMeta);
    }
    if (data.containsKey('reasoning_effort')) {
      context.handle(
          _reasoningEffortMeta,
          reasoningEffort.isAcceptableOrUnknown(
              data['reasoning_effort']!, _reasoningEffortMeta));
    }
    if (data.containsKey('tts_model')) {
      context.handle(_ttsModelMeta,
          ttsModel.isAcceptableOrUnknown(data['tts_model']!, _ttsModelMeta));
    }
    if (data.containsKey('stt_model')) {
      context.handle(_sttModelMeta,
          sttModel.isAcceptableOrUnknown(data['stt_model']!, _sttModelMeta));
    }
    if (data.containsKey('timeout_seconds')) {
      context.handle(
          _timeoutSecondsMeta,
          timeoutSeconds.isAcceptableOrUnknown(
              data['timeout_seconds']!, _timeoutSecondsMeta));
    } else if (isInserting) {
      context.missing(_timeoutSecondsMeta);
    }
    if (data.containsKey('max_tokens')) {
      context.handle(_maxTokensMeta,
          maxTokens.isAcceptableOrUnknown(data['max_tokens']!, _maxTokensMeta));
    } else if (isInserting) {
      context.missing(_maxTokensMeta);
    }
    if (data.containsKey('tts_initial_delay_ms')) {
      context.handle(
          _ttsInitialDelayMsMeta,
          ttsInitialDelayMs.isAcceptableOrUnknown(
              data['tts_initial_delay_ms']!, _ttsInitialDelayMsMeta));
    }
    if (data.containsKey('tts_text_lead_ms')) {
      context.handle(
          _ttsTextLeadMsMeta,
          ttsTextLeadMs.isAcceptableOrUnknown(
              data['tts_text_lead_ms']!, _ttsTextLeadMsMeta));
    }
    if (data.containsKey('tts_audio_path')) {
      context.handle(
          _ttsAudioPathMeta,
          ttsAudioPath.isAcceptableOrUnknown(
              data['tts_audio_path']!, _ttsAudioPathMeta));
    }
    if (data.containsKey('stt_auto_send')) {
      context.handle(
          _sttAutoSendMeta,
          sttAutoSend.isAcceptableOrUnknown(
              data['stt_auto_send']!, _sttAutoSendMeta));
    }
    if (data.containsKey('enter_to_send')) {
      context.handle(
          _enterToSendMeta,
          enterToSend.isAcceptableOrUnknown(
              data['enter_to_send']!, _enterToSendMeta));
    }
    if (data.containsKey('study_mode_enabled')) {
      context.handle(
          _studyModeEnabledMeta,
          studyModeEnabled.isAcceptableOrUnknown(
              data['study_mode_enabled']!, _studyModeEnabledMeta));
    }
    if (data.containsKey('log_directory')) {
      context.handle(
          _logDirectoryMeta,
          logDirectory.isAcceptableOrUnknown(
              data['log_directory']!, _logDirectoryMeta));
    }
    if (data.containsKey('llm_log_path')) {
      context.handle(
          _llmLogPathMeta,
          llmLogPath.isAcceptableOrUnknown(
              data['llm_log_path']!, _llmLogPathMeta));
    }
    if (data.containsKey('tts_log_path')) {
      context.handle(
          _ttsLogPathMeta,
          ttsLogPath.isAcceptableOrUnknown(
              data['tts_log_path']!, _ttsLogPathMeta));
    }
    if (data.containsKey('llm_mode')) {
      context.handle(_llmModeMeta,
          llmMode.isAcceptableOrUnknown(data['llm_mode']!, _llmModeMeta));
    } else if (isInserting) {
      context.missing(_llmModeMeta);
    }
    if (data.containsKey('locale')) {
      context.handle(_localeMeta,
          locale.isAcceptableOrUnknown(data['locale']!, _localeMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSetting(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      baseUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}base_url'])!,
      providerId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}provider_id']),
      model: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}model'])!,
      reasoningEffort: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}reasoning_effort'])!,
      ttsModel: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tts_model']),
      sttModel: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}stt_model']),
      timeoutSeconds: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}timeout_seconds'])!,
      maxTokens: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}max_tokens'])!,
      ttsInitialDelayMs: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}tts_initial_delay_ms'])!,
      ttsTextLeadMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}tts_text_lead_ms'])!,
      ttsAudioPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tts_audio_path']),
      sttAutoSend: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}stt_auto_send'])!,
      enterToSend: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}enter_to_send'])!,
      studyModeEnabled: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}study_mode_enabled'])!,
      logDirectory: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}log_directory']),
      llmLogPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}llm_log_path']),
      ttsLogPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tts_log_path']),
      llmMode: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}llm_mode'])!,
      locale: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}locale']),
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSetting extends DataClass implements Insertable<AppSetting> {
  final int id;
  final String baseUrl;
  final String? providerId;
  final String model;
  final String reasoningEffort;
  final String? ttsModel;
  final String? sttModel;
  final int timeoutSeconds;
  final int maxTokens;
  final int ttsInitialDelayMs;
  final int ttsTextLeadMs;
  final String? ttsAudioPath;
  final bool sttAutoSend;
  final bool enterToSend;
  final bool studyModeEnabled;
  final String? logDirectory;
  final String? llmLogPath;
  final String? ttsLogPath;
  final String llmMode;
  final String? locale;
  final DateTime updatedAt;
  const AppSetting(
      {required this.id,
      required this.baseUrl,
      this.providerId,
      required this.model,
      required this.reasoningEffort,
      this.ttsModel,
      this.sttModel,
      required this.timeoutSeconds,
      required this.maxTokens,
      required this.ttsInitialDelayMs,
      required this.ttsTextLeadMs,
      this.ttsAudioPath,
      required this.sttAutoSend,
      required this.enterToSend,
      required this.studyModeEnabled,
      this.logDirectory,
      this.llmLogPath,
      this.ttsLogPath,
      required this.llmMode,
      this.locale,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['base_url'] = Variable<String>(baseUrl);
    if (!nullToAbsent || providerId != null) {
      map['provider_id'] = Variable<String>(providerId);
    }
    map['model'] = Variable<String>(model);
    map['reasoning_effort'] = Variable<String>(reasoningEffort);
    if (!nullToAbsent || ttsModel != null) {
      map['tts_model'] = Variable<String>(ttsModel);
    }
    if (!nullToAbsent || sttModel != null) {
      map['stt_model'] = Variable<String>(sttModel);
    }
    map['timeout_seconds'] = Variable<int>(timeoutSeconds);
    map['max_tokens'] = Variable<int>(maxTokens);
    map['tts_initial_delay_ms'] = Variable<int>(ttsInitialDelayMs);
    map['tts_text_lead_ms'] = Variable<int>(ttsTextLeadMs);
    if (!nullToAbsent || ttsAudioPath != null) {
      map['tts_audio_path'] = Variable<String>(ttsAudioPath);
    }
    map['stt_auto_send'] = Variable<bool>(sttAutoSend);
    map['enter_to_send'] = Variable<bool>(enterToSend);
    map['study_mode_enabled'] = Variable<bool>(studyModeEnabled);
    if (!nullToAbsent || logDirectory != null) {
      map['log_directory'] = Variable<String>(logDirectory);
    }
    if (!nullToAbsent || llmLogPath != null) {
      map['llm_log_path'] = Variable<String>(llmLogPath);
    }
    if (!nullToAbsent || ttsLogPath != null) {
      map['tts_log_path'] = Variable<String>(ttsLogPath);
    }
    map['llm_mode'] = Variable<String>(llmMode);
    if (!nullToAbsent || locale != null) {
      map['locale'] = Variable<String>(locale);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(
      id: Value(id),
      baseUrl: Value(baseUrl),
      providerId: providerId == null && nullToAbsent
          ? const Value.absent()
          : Value(providerId),
      model: Value(model),
      reasoningEffort: Value(reasoningEffort),
      ttsModel: ttsModel == null && nullToAbsent
          ? const Value.absent()
          : Value(ttsModel),
      sttModel: sttModel == null && nullToAbsent
          ? const Value.absent()
          : Value(sttModel),
      timeoutSeconds: Value(timeoutSeconds),
      maxTokens: Value(maxTokens),
      ttsInitialDelayMs: Value(ttsInitialDelayMs),
      ttsTextLeadMs: Value(ttsTextLeadMs),
      ttsAudioPath: ttsAudioPath == null && nullToAbsent
          ? const Value.absent()
          : Value(ttsAudioPath),
      sttAutoSend: Value(sttAutoSend),
      enterToSend: Value(enterToSend),
      studyModeEnabled: Value(studyModeEnabled),
      logDirectory: logDirectory == null && nullToAbsent
          ? const Value.absent()
          : Value(logDirectory),
      llmLogPath: llmLogPath == null && nullToAbsent
          ? const Value.absent()
          : Value(llmLogPath),
      ttsLogPath: ttsLogPath == null && nullToAbsent
          ? const Value.absent()
          : Value(ttsLogPath),
      llmMode: Value(llmMode),
      locale:
          locale == null && nullToAbsent ? const Value.absent() : Value(locale),
      updatedAt: Value(updatedAt),
    );
  }

  factory AppSetting.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSetting(
      id: serializer.fromJson<int>(json['id']),
      baseUrl: serializer.fromJson<String>(json['baseUrl']),
      providerId: serializer.fromJson<String?>(json['providerId']),
      model: serializer.fromJson<String>(json['model']),
      reasoningEffort: serializer.fromJson<String>(json['reasoningEffort']),
      ttsModel: serializer.fromJson<String?>(json['ttsModel']),
      sttModel: serializer.fromJson<String?>(json['sttModel']),
      timeoutSeconds: serializer.fromJson<int>(json['timeoutSeconds']),
      maxTokens: serializer.fromJson<int>(json['maxTokens']),
      ttsInitialDelayMs: serializer.fromJson<int>(json['ttsInitialDelayMs']),
      ttsTextLeadMs: serializer.fromJson<int>(json['ttsTextLeadMs']),
      ttsAudioPath: serializer.fromJson<String?>(json['ttsAudioPath']),
      sttAutoSend: serializer.fromJson<bool>(json['sttAutoSend']),
      enterToSend: serializer.fromJson<bool>(json['enterToSend']),
      studyModeEnabled: serializer.fromJson<bool>(json['studyModeEnabled']),
      logDirectory: serializer.fromJson<String?>(json['logDirectory']),
      llmLogPath: serializer.fromJson<String?>(json['llmLogPath']),
      ttsLogPath: serializer.fromJson<String?>(json['ttsLogPath']),
      llmMode: serializer.fromJson<String>(json['llmMode']),
      locale: serializer.fromJson<String?>(json['locale']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'baseUrl': serializer.toJson<String>(baseUrl),
      'providerId': serializer.toJson<String?>(providerId),
      'model': serializer.toJson<String>(model),
      'reasoningEffort': serializer.toJson<String>(reasoningEffort),
      'ttsModel': serializer.toJson<String?>(ttsModel),
      'sttModel': serializer.toJson<String?>(sttModel),
      'timeoutSeconds': serializer.toJson<int>(timeoutSeconds),
      'maxTokens': serializer.toJson<int>(maxTokens),
      'ttsInitialDelayMs': serializer.toJson<int>(ttsInitialDelayMs),
      'ttsTextLeadMs': serializer.toJson<int>(ttsTextLeadMs),
      'ttsAudioPath': serializer.toJson<String?>(ttsAudioPath),
      'sttAutoSend': serializer.toJson<bool>(sttAutoSend),
      'enterToSend': serializer.toJson<bool>(enterToSend),
      'studyModeEnabled': serializer.toJson<bool>(studyModeEnabled),
      'logDirectory': serializer.toJson<String?>(logDirectory),
      'llmLogPath': serializer.toJson<String?>(llmLogPath),
      'ttsLogPath': serializer.toJson<String?>(ttsLogPath),
      'llmMode': serializer.toJson<String>(llmMode),
      'locale': serializer.toJson<String?>(locale),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  AppSetting copyWith(
          {int? id,
          String? baseUrl,
          Value<String?> providerId = const Value.absent(),
          String? model,
          String? reasoningEffort,
          Value<String?> ttsModel = const Value.absent(),
          Value<String?> sttModel = const Value.absent(),
          int? timeoutSeconds,
          int? maxTokens,
          int? ttsInitialDelayMs,
          int? ttsTextLeadMs,
          Value<String?> ttsAudioPath = const Value.absent(),
          bool? sttAutoSend,
          bool? enterToSend,
          bool? studyModeEnabled,
          Value<String?> logDirectory = const Value.absent(),
          Value<String?> llmLogPath = const Value.absent(),
          Value<String?> ttsLogPath = const Value.absent(),
          String? llmMode,
          Value<String?> locale = const Value.absent(),
          DateTime? updatedAt}) =>
      AppSetting(
        id: id ?? this.id,
        baseUrl: baseUrl ?? this.baseUrl,
        providerId: providerId.present ? providerId.value : this.providerId,
        model: model ?? this.model,
        reasoningEffort: reasoningEffort ?? this.reasoningEffort,
        ttsModel: ttsModel.present ? ttsModel.value : this.ttsModel,
        sttModel: sttModel.present ? sttModel.value : this.sttModel,
        timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
        maxTokens: maxTokens ?? this.maxTokens,
        ttsInitialDelayMs: ttsInitialDelayMs ?? this.ttsInitialDelayMs,
        ttsTextLeadMs: ttsTextLeadMs ?? this.ttsTextLeadMs,
        ttsAudioPath:
            ttsAudioPath.present ? ttsAudioPath.value : this.ttsAudioPath,
        sttAutoSend: sttAutoSend ?? this.sttAutoSend,
        enterToSend: enterToSend ?? this.enterToSend,
        studyModeEnabled: studyModeEnabled ?? this.studyModeEnabled,
        logDirectory:
            logDirectory.present ? logDirectory.value : this.logDirectory,
        llmLogPath: llmLogPath.present ? llmLogPath.value : this.llmLogPath,
        ttsLogPath: ttsLogPath.present ? ttsLogPath.value : this.ttsLogPath,
        llmMode: llmMode ?? this.llmMode,
        locale: locale.present ? locale.value : this.locale,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  AppSetting copyWithCompanion(AppSettingsCompanion data) {
    return AppSetting(
      id: data.id.present ? data.id.value : this.id,
      baseUrl: data.baseUrl.present ? data.baseUrl.value : this.baseUrl,
      providerId:
          data.providerId.present ? data.providerId.value : this.providerId,
      model: data.model.present ? data.model.value : this.model,
      reasoningEffort: data.reasoningEffort.present
          ? data.reasoningEffort.value
          : this.reasoningEffort,
      ttsModel: data.ttsModel.present ? data.ttsModel.value : this.ttsModel,
      sttModel: data.sttModel.present ? data.sttModel.value : this.sttModel,
      timeoutSeconds: data.timeoutSeconds.present
          ? data.timeoutSeconds.value
          : this.timeoutSeconds,
      maxTokens: data.maxTokens.present ? data.maxTokens.value : this.maxTokens,
      ttsInitialDelayMs: data.ttsInitialDelayMs.present
          ? data.ttsInitialDelayMs.value
          : this.ttsInitialDelayMs,
      ttsTextLeadMs: data.ttsTextLeadMs.present
          ? data.ttsTextLeadMs.value
          : this.ttsTextLeadMs,
      ttsAudioPath: data.ttsAudioPath.present
          ? data.ttsAudioPath.value
          : this.ttsAudioPath,
      sttAutoSend:
          data.sttAutoSend.present ? data.sttAutoSend.value : this.sttAutoSend,
      enterToSend:
          data.enterToSend.present ? data.enterToSend.value : this.enterToSend,
      studyModeEnabled: data.studyModeEnabled.present
          ? data.studyModeEnabled.value
          : this.studyModeEnabled,
      logDirectory: data.logDirectory.present
          ? data.logDirectory.value
          : this.logDirectory,
      llmLogPath:
          data.llmLogPath.present ? data.llmLogPath.value : this.llmLogPath,
      ttsLogPath:
          data.ttsLogPath.present ? data.ttsLogPath.value : this.ttsLogPath,
      llmMode: data.llmMode.present ? data.llmMode.value : this.llmMode,
      locale: data.locale.present ? data.locale.value : this.locale,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSetting(')
          ..write('id: $id, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('providerId: $providerId, ')
          ..write('model: $model, ')
          ..write('reasoningEffort: $reasoningEffort, ')
          ..write('ttsModel: $ttsModel, ')
          ..write('sttModel: $sttModel, ')
          ..write('timeoutSeconds: $timeoutSeconds, ')
          ..write('maxTokens: $maxTokens, ')
          ..write('ttsInitialDelayMs: $ttsInitialDelayMs, ')
          ..write('ttsTextLeadMs: $ttsTextLeadMs, ')
          ..write('ttsAudioPath: $ttsAudioPath, ')
          ..write('sttAutoSend: $sttAutoSend, ')
          ..write('enterToSend: $enterToSend, ')
          ..write('studyModeEnabled: $studyModeEnabled, ')
          ..write('logDirectory: $logDirectory, ')
          ..write('llmLogPath: $llmLogPath, ')
          ..write('ttsLogPath: $ttsLogPath, ')
          ..write('llmMode: $llmMode, ')
          ..write('locale: $locale, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        baseUrl,
        providerId,
        model,
        reasoningEffort,
        ttsModel,
        sttModel,
        timeoutSeconds,
        maxTokens,
        ttsInitialDelayMs,
        ttsTextLeadMs,
        ttsAudioPath,
        sttAutoSend,
        enterToSend,
        studyModeEnabled,
        logDirectory,
        llmLogPath,
        ttsLogPath,
        llmMode,
        locale,
        updatedAt
      ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSetting &&
          other.id == this.id &&
          other.baseUrl == this.baseUrl &&
          other.providerId == this.providerId &&
          other.model == this.model &&
          other.reasoningEffort == this.reasoningEffort &&
          other.ttsModel == this.ttsModel &&
          other.sttModel == this.sttModel &&
          other.timeoutSeconds == this.timeoutSeconds &&
          other.maxTokens == this.maxTokens &&
          other.ttsInitialDelayMs == this.ttsInitialDelayMs &&
          other.ttsTextLeadMs == this.ttsTextLeadMs &&
          other.ttsAudioPath == this.ttsAudioPath &&
          other.sttAutoSend == this.sttAutoSend &&
          other.enterToSend == this.enterToSend &&
          other.studyModeEnabled == this.studyModeEnabled &&
          other.logDirectory == this.logDirectory &&
          other.llmLogPath == this.llmLogPath &&
          other.ttsLogPath == this.ttsLogPath &&
          other.llmMode == this.llmMode &&
          other.locale == this.locale &&
          other.updatedAt == this.updatedAt);
}

class AppSettingsCompanion extends UpdateCompanion<AppSetting> {
  final Value<int> id;
  final Value<String> baseUrl;
  final Value<String?> providerId;
  final Value<String> model;
  final Value<String> reasoningEffort;
  final Value<String?> ttsModel;
  final Value<String?> sttModel;
  final Value<int> timeoutSeconds;
  final Value<int> maxTokens;
  final Value<int> ttsInitialDelayMs;
  final Value<int> ttsTextLeadMs;
  final Value<String?> ttsAudioPath;
  final Value<bool> sttAutoSend;
  final Value<bool> enterToSend;
  final Value<bool> studyModeEnabled;
  final Value<String?> logDirectory;
  final Value<String?> llmLogPath;
  final Value<String?> ttsLogPath;
  final Value<String> llmMode;
  final Value<String?> locale;
  final Value<DateTime> updatedAt;
  const AppSettingsCompanion({
    this.id = const Value.absent(),
    this.baseUrl = const Value.absent(),
    this.providerId = const Value.absent(),
    this.model = const Value.absent(),
    this.reasoningEffort = const Value.absent(),
    this.ttsModel = const Value.absent(),
    this.sttModel = const Value.absent(),
    this.timeoutSeconds = const Value.absent(),
    this.maxTokens = const Value.absent(),
    this.ttsInitialDelayMs = const Value.absent(),
    this.ttsTextLeadMs = const Value.absent(),
    this.ttsAudioPath = const Value.absent(),
    this.sttAutoSend = const Value.absent(),
    this.enterToSend = const Value.absent(),
    this.studyModeEnabled = const Value.absent(),
    this.logDirectory = const Value.absent(),
    this.llmLogPath = const Value.absent(),
    this.ttsLogPath = const Value.absent(),
    this.llmMode = const Value.absent(),
    this.locale = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    this.id = const Value.absent(),
    required String baseUrl,
    this.providerId = const Value.absent(),
    required String model,
    this.reasoningEffort = const Value.absent(),
    this.ttsModel = const Value.absent(),
    this.sttModel = const Value.absent(),
    required int timeoutSeconds,
    required int maxTokens,
    this.ttsInitialDelayMs = const Value.absent(),
    this.ttsTextLeadMs = const Value.absent(),
    this.ttsAudioPath = const Value.absent(),
    this.sttAutoSend = const Value.absent(),
    this.enterToSend = const Value.absent(),
    this.studyModeEnabled = const Value.absent(),
    this.logDirectory = const Value.absent(),
    this.llmLogPath = const Value.absent(),
    this.ttsLogPath = const Value.absent(),
    required String llmMode,
    this.locale = const Value.absent(),
    this.updatedAt = const Value.absent(),
  })  : baseUrl = Value(baseUrl),
        model = Value(model),
        timeoutSeconds = Value(timeoutSeconds),
        maxTokens = Value(maxTokens),
        llmMode = Value(llmMode);
  static Insertable<AppSetting> custom({
    Expression<int>? id,
    Expression<String>? baseUrl,
    Expression<String>? providerId,
    Expression<String>? model,
    Expression<String>? reasoningEffort,
    Expression<String>? ttsModel,
    Expression<String>? sttModel,
    Expression<int>? timeoutSeconds,
    Expression<int>? maxTokens,
    Expression<int>? ttsInitialDelayMs,
    Expression<int>? ttsTextLeadMs,
    Expression<String>? ttsAudioPath,
    Expression<bool>? sttAutoSend,
    Expression<bool>? enterToSend,
    Expression<bool>? studyModeEnabled,
    Expression<String>? logDirectory,
    Expression<String>? llmLogPath,
    Expression<String>? ttsLogPath,
    Expression<String>? llmMode,
    Expression<String>? locale,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (baseUrl != null) 'base_url': baseUrl,
      if (providerId != null) 'provider_id': providerId,
      if (model != null) 'model': model,
      if (reasoningEffort != null) 'reasoning_effort': reasoningEffort,
      if (ttsModel != null) 'tts_model': ttsModel,
      if (sttModel != null) 'stt_model': sttModel,
      if (timeoutSeconds != null) 'timeout_seconds': timeoutSeconds,
      if (maxTokens != null) 'max_tokens': maxTokens,
      if (ttsInitialDelayMs != null) 'tts_initial_delay_ms': ttsInitialDelayMs,
      if (ttsTextLeadMs != null) 'tts_text_lead_ms': ttsTextLeadMs,
      if (ttsAudioPath != null) 'tts_audio_path': ttsAudioPath,
      if (sttAutoSend != null) 'stt_auto_send': sttAutoSend,
      if (enterToSend != null) 'enter_to_send': enterToSend,
      if (studyModeEnabled != null) 'study_mode_enabled': studyModeEnabled,
      if (logDirectory != null) 'log_directory': logDirectory,
      if (llmLogPath != null) 'llm_log_path': llmLogPath,
      if (ttsLogPath != null) 'tts_log_path': ttsLogPath,
      if (llmMode != null) 'llm_mode': llmMode,
      if (locale != null) 'locale': locale,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  AppSettingsCompanion copyWith(
      {Value<int>? id,
      Value<String>? baseUrl,
      Value<String?>? providerId,
      Value<String>? model,
      Value<String>? reasoningEffort,
      Value<String?>? ttsModel,
      Value<String?>? sttModel,
      Value<int>? timeoutSeconds,
      Value<int>? maxTokens,
      Value<int>? ttsInitialDelayMs,
      Value<int>? ttsTextLeadMs,
      Value<String?>? ttsAudioPath,
      Value<bool>? sttAutoSend,
      Value<bool>? enterToSend,
      Value<bool>? studyModeEnabled,
      Value<String?>? logDirectory,
      Value<String?>? llmLogPath,
      Value<String?>? ttsLogPath,
      Value<String>? llmMode,
      Value<String?>? locale,
      Value<DateTime>? updatedAt}) {
    return AppSettingsCompanion(
      id: id ?? this.id,
      baseUrl: baseUrl ?? this.baseUrl,
      providerId: providerId ?? this.providerId,
      model: model ?? this.model,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      ttsModel: ttsModel ?? this.ttsModel,
      sttModel: sttModel ?? this.sttModel,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      maxTokens: maxTokens ?? this.maxTokens,
      ttsInitialDelayMs: ttsInitialDelayMs ?? this.ttsInitialDelayMs,
      ttsTextLeadMs: ttsTextLeadMs ?? this.ttsTextLeadMs,
      ttsAudioPath: ttsAudioPath ?? this.ttsAudioPath,
      sttAutoSend: sttAutoSend ?? this.sttAutoSend,
      enterToSend: enterToSend ?? this.enterToSend,
      studyModeEnabled: studyModeEnabled ?? this.studyModeEnabled,
      logDirectory: logDirectory ?? this.logDirectory,
      llmLogPath: llmLogPath ?? this.llmLogPath,
      ttsLogPath: ttsLogPath ?? this.ttsLogPath,
      llmMode: llmMode ?? this.llmMode,
      locale: locale ?? this.locale,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (baseUrl.present) {
      map['base_url'] = Variable<String>(baseUrl.value);
    }
    if (providerId.present) {
      map['provider_id'] = Variable<String>(providerId.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (reasoningEffort.present) {
      map['reasoning_effort'] = Variable<String>(reasoningEffort.value);
    }
    if (ttsModel.present) {
      map['tts_model'] = Variable<String>(ttsModel.value);
    }
    if (sttModel.present) {
      map['stt_model'] = Variable<String>(sttModel.value);
    }
    if (timeoutSeconds.present) {
      map['timeout_seconds'] = Variable<int>(timeoutSeconds.value);
    }
    if (maxTokens.present) {
      map['max_tokens'] = Variable<int>(maxTokens.value);
    }
    if (ttsInitialDelayMs.present) {
      map['tts_initial_delay_ms'] = Variable<int>(ttsInitialDelayMs.value);
    }
    if (ttsTextLeadMs.present) {
      map['tts_text_lead_ms'] = Variable<int>(ttsTextLeadMs.value);
    }
    if (ttsAudioPath.present) {
      map['tts_audio_path'] = Variable<String>(ttsAudioPath.value);
    }
    if (sttAutoSend.present) {
      map['stt_auto_send'] = Variable<bool>(sttAutoSend.value);
    }
    if (enterToSend.present) {
      map['enter_to_send'] = Variable<bool>(enterToSend.value);
    }
    if (studyModeEnabled.present) {
      map['study_mode_enabled'] = Variable<bool>(studyModeEnabled.value);
    }
    if (logDirectory.present) {
      map['log_directory'] = Variable<String>(logDirectory.value);
    }
    if (llmLogPath.present) {
      map['llm_log_path'] = Variable<String>(llmLogPath.value);
    }
    if (ttsLogPath.present) {
      map['tts_log_path'] = Variable<String>(ttsLogPath.value);
    }
    if (llmMode.present) {
      map['llm_mode'] = Variable<String>(llmMode.value);
    }
    if (locale.present) {
      map['locale'] = Variable<String>(locale.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('id: $id, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('providerId: $providerId, ')
          ..write('model: $model, ')
          ..write('reasoningEffort: $reasoningEffort, ')
          ..write('ttsModel: $ttsModel, ')
          ..write('sttModel: $sttModel, ')
          ..write('timeoutSeconds: $timeoutSeconds, ')
          ..write('maxTokens: $maxTokens, ')
          ..write('ttsInitialDelayMs: $ttsInitialDelayMs, ')
          ..write('ttsTextLeadMs: $ttsTextLeadMs, ')
          ..write('ttsAudioPath: $ttsAudioPath, ')
          ..write('sttAutoSend: $sttAutoSend, ')
          ..write('enterToSend: $enterToSend, ')
          ..write('studyModeEnabled: $studyModeEnabled, ')
          ..write('logDirectory: $logDirectory, ')
          ..write('llmLogPath: $llmLogPath, ')
          ..write('ttsLogPath: $ttsLogPath, ')
          ..write('llmMode: $llmMode, ')
          ..write('locale: $locale, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $ApiConfigsTable extends ApiConfigs
    with TableInfo<$ApiConfigsTable, ApiConfig> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ApiConfigsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _baseUrlMeta =
      const VerificationMeta('baseUrl');
  @override
  late final GeneratedColumn<String> baseUrl = GeneratedColumn<String>(
      'base_url', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
      'model', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _reasoningEffortMeta =
      const VerificationMeta('reasoningEffort');
  @override
  late final GeneratedColumn<String> reasoningEffort = GeneratedColumn<String>(
      'reasoning_effort', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('medium'));
  static const VerificationMeta _ttsModelMeta =
      const VerificationMeta('ttsModel');
  @override
  late final GeneratedColumn<String> ttsModel = GeneratedColumn<String>(
      'tts_model', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _sttModelMeta =
      const VerificationMeta('sttModel');
  @override
  late final GeneratedColumn<String> sttModel = GeneratedColumn<String>(
      'stt_model', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _apiKeyHashMeta =
      const VerificationMeta('apiKeyHash');
  @override
  late final GeneratedColumn<String> apiKeyHash = GeneratedColumn<String>(
      'api_key_hash', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        baseUrl,
        model,
        reasoningEffort,
        ttsModel,
        sttModel,
        apiKeyHash,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'api_configs';
  @override
  VerificationContext validateIntegrity(Insertable<ApiConfig> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('base_url')) {
      context.handle(_baseUrlMeta,
          baseUrl.isAcceptableOrUnknown(data['base_url']!, _baseUrlMeta));
    } else if (isInserting) {
      context.missing(_baseUrlMeta);
    }
    if (data.containsKey('model')) {
      context.handle(
          _modelMeta, model.isAcceptableOrUnknown(data['model']!, _modelMeta));
    } else if (isInserting) {
      context.missing(_modelMeta);
    }
    if (data.containsKey('reasoning_effort')) {
      context.handle(
          _reasoningEffortMeta,
          reasoningEffort.isAcceptableOrUnknown(
              data['reasoning_effort']!, _reasoningEffortMeta));
    }
    if (data.containsKey('tts_model')) {
      context.handle(_ttsModelMeta,
          ttsModel.isAcceptableOrUnknown(data['tts_model']!, _ttsModelMeta));
    }
    if (data.containsKey('stt_model')) {
      context.handle(_sttModelMeta,
          sttModel.isAcceptableOrUnknown(data['stt_model']!, _sttModelMeta));
    }
    if (data.containsKey('api_key_hash')) {
      context.handle(
          _apiKeyHashMeta,
          apiKeyHash.isAcceptableOrUnknown(
              data['api_key_hash']!, _apiKeyHashMeta));
    } else if (isInserting) {
      context.missing(_apiKeyHashMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
        {baseUrl, model, reasoningEffort, ttsModel, sttModel, apiKeyHash},
      ];
  @override
  ApiConfig map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ApiConfig(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      baseUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}base_url'])!,
      model: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}model'])!,
      reasoningEffort: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}reasoning_effort'])!,
      ttsModel: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tts_model']),
      sttModel: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}stt_model']),
      apiKeyHash: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}api_key_hash'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $ApiConfigsTable createAlias(String alias) {
    return $ApiConfigsTable(attachedDatabase, alias);
  }
}

class ApiConfig extends DataClass implements Insertable<ApiConfig> {
  final int id;
  final String baseUrl;
  final String model;
  final String reasoningEffort;
  final String? ttsModel;
  final String? sttModel;
  final String apiKeyHash;
  final DateTime createdAt;
  const ApiConfig(
      {required this.id,
      required this.baseUrl,
      required this.model,
      required this.reasoningEffort,
      this.ttsModel,
      this.sttModel,
      required this.apiKeyHash,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['base_url'] = Variable<String>(baseUrl);
    map['model'] = Variable<String>(model);
    map['reasoning_effort'] = Variable<String>(reasoningEffort);
    if (!nullToAbsent || ttsModel != null) {
      map['tts_model'] = Variable<String>(ttsModel);
    }
    if (!nullToAbsent || sttModel != null) {
      map['stt_model'] = Variable<String>(sttModel);
    }
    map['api_key_hash'] = Variable<String>(apiKeyHash);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ApiConfigsCompanion toCompanion(bool nullToAbsent) {
    return ApiConfigsCompanion(
      id: Value(id),
      baseUrl: Value(baseUrl),
      model: Value(model),
      reasoningEffort: Value(reasoningEffort),
      ttsModel: ttsModel == null && nullToAbsent
          ? const Value.absent()
          : Value(ttsModel),
      sttModel: sttModel == null && nullToAbsent
          ? const Value.absent()
          : Value(sttModel),
      apiKeyHash: Value(apiKeyHash),
      createdAt: Value(createdAt),
    );
  }

  factory ApiConfig.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ApiConfig(
      id: serializer.fromJson<int>(json['id']),
      baseUrl: serializer.fromJson<String>(json['baseUrl']),
      model: serializer.fromJson<String>(json['model']),
      reasoningEffort: serializer.fromJson<String>(json['reasoningEffort']),
      ttsModel: serializer.fromJson<String?>(json['ttsModel']),
      sttModel: serializer.fromJson<String?>(json['sttModel']),
      apiKeyHash: serializer.fromJson<String>(json['apiKeyHash']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'baseUrl': serializer.toJson<String>(baseUrl),
      'model': serializer.toJson<String>(model),
      'reasoningEffort': serializer.toJson<String>(reasoningEffort),
      'ttsModel': serializer.toJson<String?>(ttsModel),
      'sttModel': serializer.toJson<String?>(sttModel),
      'apiKeyHash': serializer.toJson<String>(apiKeyHash),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ApiConfig copyWith(
          {int? id,
          String? baseUrl,
          String? model,
          String? reasoningEffort,
          Value<String?> ttsModel = const Value.absent(),
          Value<String?> sttModel = const Value.absent(),
          String? apiKeyHash,
          DateTime? createdAt}) =>
      ApiConfig(
        id: id ?? this.id,
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
        reasoningEffort: reasoningEffort ?? this.reasoningEffort,
        ttsModel: ttsModel.present ? ttsModel.value : this.ttsModel,
        sttModel: sttModel.present ? sttModel.value : this.sttModel,
        apiKeyHash: apiKeyHash ?? this.apiKeyHash,
        createdAt: createdAt ?? this.createdAt,
      );
  ApiConfig copyWithCompanion(ApiConfigsCompanion data) {
    return ApiConfig(
      id: data.id.present ? data.id.value : this.id,
      baseUrl: data.baseUrl.present ? data.baseUrl.value : this.baseUrl,
      model: data.model.present ? data.model.value : this.model,
      reasoningEffort: data.reasoningEffort.present
          ? data.reasoningEffort.value
          : this.reasoningEffort,
      ttsModel: data.ttsModel.present ? data.ttsModel.value : this.ttsModel,
      sttModel: data.sttModel.present ? data.sttModel.value : this.sttModel,
      apiKeyHash:
          data.apiKeyHash.present ? data.apiKeyHash.value : this.apiKeyHash,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ApiConfig(')
          ..write('id: $id, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('model: $model, ')
          ..write('reasoningEffort: $reasoningEffort, ')
          ..write('ttsModel: $ttsModel, ')
          ..write('sttModel: $sttModel, ')
          ..write('apiKeyHash: $apiKeyHash, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, baseUrl, model, reasoningEffort, ttsModel,
      sttModel, apiKeyHash, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ApiConfig &&
          other.id == this.id &&
          other.baseUrl == this.baseUrl &&
          other.model == this.model &&
          other.reasoningEffort == this.reasoningEffort &&
          other.ttsModel == this.ttsModel &&
          other.sttModel == this.sttModel &&
          other.apiKeyHash == this.apiKeyHash &&
          other.createdAt == this.createdAt);
}

class ApiConfigsCompanion extends UpdateCompanion<ApiConfig> {
  final Value<int> id;
  final Value<String> baseUrl;
  final Value<String> model;
  final Value<String> reasoningEffort;
  final Value<String?> ttsModel;
  final Value<String?> sttModel;
  final Value<String> apiKeyHash;
  final Value<DateTime> createdAt;
  const ApiConfigsCompanion({
    this.id = const Value.absent(),
    this.baseUrl = const Value.absent(),
    this.model = const Value.absent(),
    this.reasoningEffort = const Value.absent(),
    this.ttsModel = const Value.absent(),
    this.sttModel = const Value.absent(),
    this.apiKeyHash = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  ApiConfigsCompanion.insert({
    this.id = const Value.absent(),
    required String baseUrl,
    required String model,
    this.reasoningEffort = const Value.absent(),
    this.ttsModel = const Value.absent(),
    this.sttModel = const Value.absent(),
    required String apiKeyHash,
    this.createdAt = const Value.absent(),
  })  : baseUrl = Value(baseUrl),
        model = Value(model),
        apiKeyHash = Value(apiKeyHash);
  static Insertable<ApiConfig> custom({
    Expression<int>? id,
    Expression<String>? baseUrl,
    Expression<String>? model,
    Expression<String>? reasoningEffort,
    Expression<String>? ttsModel,
    Expression<String>? sttModel,
    Expression<String>? apiKeyHash,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (baseUrl != null) 'base_url': baseUrl,
      if (model != null) 'model': model,
      if (reasoningEffort != null) 'reasoning_effort': reasoningEffort,
      if (ttsModel != null) 'tts_model': ttsModel,
      if (sttModel != null) 'stt_model': sttModel,
      if (apiKeyHash != null) 'api_key_hash': apiKeyHash,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  ApiConfigsCompanion copyWith(
      {Value<int>? id,
      Value<String>? baseUrl,
      Value<String>? model,
      Value<String>? reasoningEffort,
      Value<String?>? ttsModel,
      Value<String?>? sttModel,
      Value<String>? apiKeyHash,
      Value<DateTime>? createdAt}) {
    return ApiConfigsCompanion(
      id: id ?? this.id,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      ttsModel: ttsModel ?? this.ttsModel,
      sttModel: sttModel ?? this.sttModel,
      apiKeyHash: apiKeyHash ?? this.apiKeyHash,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (baseUrl.present) {
      map['base_url'] = Variable<String>(baseUrl.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (reasoningEffort.present) {
      map['reasoning_effort'] = Variable<String>(reasoningEffort.value);
    }
    if (ttsModel.present) {
      map['tts_model'] = Variable<String>(ttsModel.value);
    }
    if (sttModel.present) {
      map['stt_model'] = Variable<String>(sttModel.value);
    }
    if (apiKeyHash.present) {
      map['api_key_hash'] = Variable<String>(apiKeyHash.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ApiConfigsCompanion(')
          ..write('id: $id, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('model: $model, ')
          ..write('reasoningEffort: $reasoningEffort, ')
          ..write('ttsModel: $ttsModel, ')
          ..write('sttModel: $sttModel, ')
          ..write('apiKeyHash: $apiKeyHash, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $PromptTemplatesTable extends PromptTemplates
    with TableInfo<$PromptTemplatesTable, PromptTemplate> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PromptTemplatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _teacherIdMeta =
      const VerificationMeta('teacherId');
  @override
  late final GeneratedColumn<int> teacherId = GeneratedColumn<int>(
      'teacher_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _courseKeyMeta =
      const VerificationMeta('courseKey');
  @override
  late final GeneratedColumn<String> courseKey = GeneratedColumn<String>(
      'course_key', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _studentIdMeta =
      const VerificationMeta('studentId');
  @override
  late final GeneratedColumn<int> studentId = GeneratedColumn<int>(
      'student_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _promptNameMeta =
      const VerificationMeta('promptName');
  @override
  late final GeneratedColumn<String> promptName = GeneratedColumn<String>(
      'prompt_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _contentMeta =
      const VerificationMeta('content');
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
      'content', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _isActiveMeta =
      const VerificationMeta('isActive');
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
      'is_active', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_active" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        teacherId,
        courseKey,
        studentId,
        promptName,
        content,
        isActive,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'prompt_templates';
  @override
  VerificationContext validateIntegrity(Insertable<PromptTemplate> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('teacher_id')) {
      context.handle(_teacherIdMeta,
          teacherId.isAcceptableOrUnknown(data['teacher_id']!, _teacherIdMeta));
    } else if (isInserting) {
      context.missing(_teacherIdMeta);
    }
    if (data.containsKey('course_key')) {
      context.handle(_courseKeyMeta,
          courseKey.isAcceptableOrUnknown(data['course_key']!, _courseKeyMeta));
    }
    if (data.containsKey('student_id')) {
      context.handle(_studentIdMeta,
          studentId.isAcceptableOrUnknown(data['student_id']!, _studentIdMeta));
    }
    if (data.containsKey('prompt_name')) {
      context.handle(
          _promptNameMeta,
          promptName.isAcceptableOrUnknown(
              data['prompt_name']!, _promptNameMeta));
    } else if (isInserting) {
      context.missing(_promptNameMeta);
    }
    if (data.containsKey('content')) {
      context.handle(_contentMeta,
          content.isAcceptableOrUnknown(data['content']!, _contentMeta));
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('is_active')) {
      context.handle(_isActiveMeta,
          isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PromptTemplate map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PromptTemplate(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      teacherId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}teacher_id'])!,
      courseKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}course_key']),
      studentId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}student_id']),
      promptName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}prompt_name'])!,
      content: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content'])!,
      isActive: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_active'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $PromptTemplatesTable createAlias(String alias) {
    return $PromptTemplatesTable(attachedDatabase, alias);
  }
}

class PromptTemplate extends DataClass implements Insertable<PromptTemplate> {
  final int id;
  final int teacherId;
  final String? courseKey;
  final int? studentId;
  final String promptName;
  final String content;
  final bool isActive;
  final DateTime createdAt;
  const PromptTemplate(
      {required this.id,
      required this.teacherId,
      this.courseKey,
      this.studentId,
      required this.promptName,
      required this.content,
      required this.isActive,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['teacher_id'] = Variable<int>(teacherId);
    if (!nullToAbsent || courseKey != null) {
      map['course_key'] = Variable<String>(courseKey);
    }
    if (!nullToAbsent || studentId != null) {
      map['student_id'] = Variable<int>(studentId);
    }
    map['prompt_name'] = Variable<String>(promptName);
    map['content'] = Variable<String>(content);
    map['is_active'] = Variable<bool>(isActive);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  PromptTemplatesCompanion toCompanion(bool nullToAbsent) {
    return PromptTemplatesCompanion(
      id: Value(id),
      teacherId: Value(teacherId),
      courseKey: courseKey == null && nullToAbsent
          ? const Value.absent()
          : Value(courseKey),
      studentId: studentId == null && nullToAbsent
          ? const Value.absent()
          : Value(studentId),
      promptName: Value(promptName),
      content: Value(content),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
    );
  }

  factory PromptTemplate.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PromptTemplate(
      id: serializer.fromJson<int>(json['id']),
      teacherId: serializer.fromJson<int>(json['teacherId']),
      courseKey: serializer.fromJson<String?>(json['courseKey']),
      studentId: serializer.fromJson<int?>(json['studentId']),
      promptName: serializer.fromJson<String>(json['promptName']),
      content: serializer.fromJson<String>(json['content']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'teacherId': serializer.toJson<int>(teacherId),
      'courseKey': serializer.toJson<String?>(courseKey),
      'studentId': serializer.toJson<int?>(studentId),
      'promptName': serializer.toJson<String>(promptName),
      'content': serializer.toJson<String>(content),
      'isActive': serializer.toJson<bool>(isActive),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  PromptTemplate copyWith(
          {int? id,
          int? teacherId,
          Value<String?> courseKey = const Value.absent(),
          Value<int?> studentId = const Value.absent(),
          String? promptName,
          String? content,
          bool? isActive,
          DateTime? createdAt}) =>
      PromptTemplate(
        id: id ?? this.id,
        teacherId: teacherId ?? this.teacherId,
        courseKey: courseKey.present ? courseKey.value : this.courseKey,
        studentId: studentId.present ? studentId.value : this.studentId,
        promptName: promptName ?? this.promptName,
        content: content ?? this.content,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt ?? this.createdAt,
      );
  PromptTemplate copyWithCompanion(PromptTemplatesCompanion data) {
    return PromptTemplate(
      id: data.id.present ? data.id.value : this.id,
      teacherId: data.teacherId.present ? data.teacherId.value : this.teacherId,
      courseKey: data.courseKey.present ? data.courseKey.value : this.courseKey,
      studentId: data.studentId.present ? data.studentId.value : this.studentId,
      promptName:
          data.promptName.present ? data.promptName.value : this.promptName,
      content: data.content.present ? data.content.value : this.content,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PromptTemplate(')
          ..write('id: $id, ')
          ..write('teacherId: $teacherId, ')
          ..write('courseKey: $courseKey, ')
          ..write('studentId: $studentId, ')
          ..write('promptName: $promptName, ')
          ..write('content: $content, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, teacherId, courseKey, studentId,
      promptName, content, isActive, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PromptTemplate &&
          other.id == this.id &&
          other.teacherId == this.teacherId &&
          other.courseKey == this.courseKey &&
          other.studentId == this.studentId &&
          other.promptName == this.promptName &&
          other.content == this.content &&
          other.isActive == this.isActive &&
          other.createdAt == this.createdAt);
}

class PromptTemplatesCompanion extends UpdateCompanion<PromptTemplate> {
  final Value<int> id;
  final Value<int> teacherId;
  final Value<String?> courseKey;
  final Value<int?> studentId;
  final Value<String> promptName;
  final Value<String> content;
  final Value<bool> isActive;
  final Value<DateTime> createdAt;
  const PromptTemplatesCompanion({
    this.id = const Value.absent(),
    this.teacherId = const Value.absent(),
    this.courseKey = const Value.absent(),
    this.studentId = const Value.absent(),
    this.promptName = const Value.absent(),
    this.content = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  PromptTemplatesCompanion.insert({
    this.id = const Value.absent(),
    required int teacherId,
    this.courseKey = const Value.absent(),
    this.studentId = const Value.absent(),
    required String promptName,
    required String content,
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
  })  : teacherId = Value(teacherId),
        promptName = Value(promptName),
        content = Value(content);
  static Insertable<PromptTemplate> custom({
    Expression<int>? id,
    Expression<int>? teacherId,
    Expression<String>? courseKey,
    Expression<int>? studentId,
    Expression<String>? promptName,
    Expression<String>? content,
    Expression<bool>? isActive,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (teacherId != null) 'teacher_id': teacherId,
      if (courseKey != null) 'course_key': courseKey,
      if (studentId != null) 'student_id': studentId,
      if (promptName != null) 'prompt_name': promptName,
      if (content != null) 'content': content,
      if (isActive != null) 'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  PromptTemplatesCompanion copyWith(
      {Value<int>? id,
      Value<int>? teacherId,
      Value<String?>? courseKey,
      Value<int?>? studentId,
      Value<String>? promptName,
      Value<String>? content,
      Value<bool>? isActive,
      Value<DateTime>? createdAt}) {
    return PromptTemplatesCompanion(
      id: id ?? this.id,
      teacherId: teacherId ?? this.teacherId,
      courseKey: courseKey ?? this.courseKey,
      studentId: studentId ?? this.studentId,
      promptName: promptName ?? this.promptName,
      content: content ?? this.content,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (teacherId.present) {
      map['teacher_id'] = Variable<int>(teacherId.value);
    }
    if (courseKey.present) {
      map['course_key'] = Variable<String>(courseKey.value);
    }
    if (studentId.present) {
      map['student_id'] = Variable<int>(studentId.value);
    }
    if (promptName.present) {
      map['prompt_name'] = Variable<String>(promptName.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PromptTemplatesCompanion(')
          ..write('id: $id, ')
          ..write('teacherId: $teacherId, ')
          ..write('courseKey: $courseKey, ')
          ..write('studentId: $studentId, ')
          ..write('promptName: $promptName, ')
          ..write('content: $content, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $StudentPromptProfilesTable extends StudentPromptProfiles
    with TableInfo<$StudentPromptProfilesTable, StudentPromptProfile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StudentPromptProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _teacherIdMeta =
      const VerificationMeta('teacherId');
  @override
  late final GeneratedColumn<int> teacherId = GeneratedColumn<int>(
      'teacher_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _courseKeyMeta =
      const VerificationMeta('courseKey');
  @override
  late final GeneratedColumn<String> courseKey = GeneratedColumn<String>(
      'course_key', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _studentIdMeta =
      const VerificationMeta('studentId');
  @override
  late final GeneratedColumn<int> studentId = GeneratedColumn<int>(
      'student_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _gradeLevelMeta =
      const VerificationMeta('gradeLevel');
  @override
  late final GeneratedColumn<String> gradeLevel = GeneratedColumn<String>(
      'grade_level', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _readingLevelMeta =
      const VerificationMeta('readingLevel');
  @override
  late final GeneratedColumn<String> readingLevel = GeneratedColumn<String>(
      'reading_level', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _preferredLanguageMeta =
      const VerificationMeta('preferredLanguage');
  @override
  late final GeneratedColumn<String> preferredLanguage =
      GeneratedColumn<String>('preferred_language', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _interestsMeta =
      const VerificationMeta('interests');
  @override
  late final GeneratedColumn<String> interests = GeneratedColumn<String>(
      'interests', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _preferredToneMeta =
      const VerificationMeta('preferredTone');
  @override
  late final GeneratedColumn<String> preferredTone = GeneratedColumn<String>(
      'preferred_tone', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _preferredPaceMeta =
      const VerificationMeta('preferredPace');
  @override
  late final GeneratedColumn<String> preferredPace = GeneratedColumn<String>(
      'preferred_pace', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _preferredFormatMeta =
      const VerificationMeta('preferredFormat');
  @override
  late final GeneratedColumn<String> preferredFormat = GeneratedColumn<String>(
      'preferred_format', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _supportNotesMeta =
      const VerificationMeta('supportNotes');
  @override
  late final GeneratedColumn<String> supportNotes = GeneratedColumn<String>(
      'support_notes', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        teacherId,
        courseKey,
        studentId,
        gradeLevel,
        readingLevel,
        preferredLanguage,
        interests,
        preferredTone,
        preferredPace,
        preferredFormat,
        supportNotes,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'student_prompt_profiles';
  @override
  VerificationContext validateIntegrity(
      Insertable<StudentPromptProfile> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('teacher_id')) {
      context.handle(_teacherIdMeta,
          teacherId.isAcceptableOrUnknown(data['teacher_id']!, _teacherIdMeta));
    } else if (isInserting) {
      context.missing(_teacherIdMeta);
    }
    if (data.containsKey('course_key')) {
      context.handle(_courseKeyMeta,
          courseKey.isAcceptableOrUnknown(data['course_key']!, _courseKeyMeta));
    }
    if (data.containsKey('student_id')) {
      context.handle(_studentIdMeta,
          studentId.isAcceptableOrUnknown(data['student_id']!, _studentIdMeta));
    }
    if (data.containsKey('grade_level')) {
      context.handle(
          _gradeLevelMeta,
          gradeLevel.isAcceptableOrUnknown(
              data['grade_level']!, _gradeLevelMeta));
    }
    if (data.containsKey('reading_level')) {
      context.handle(
          _readingLevelMeta,
          readingLevel.isAcceptableOrUnknown(
              data['reading_level']!, _readingLevelMeta));
    }
    if (data.containsKey('preferred_language')) {
      context.handle(
          _preferredLanguageMeta,
          preferredLanguage.isAcceptableOrUnknown(
              data['preferred_language']!, _preferredLanguageMeta));
    }
    if (data.containsKey('interests')) {
      context.handle(_interestsMeta,
          interests.isAcceptableOrUnknown(data['interests']!, _interestsMeta));
    }
    if (data.containsKey('preferred_tone')) {
      context.handle(
          _preferredToneMeta,
          preferredTone.isAcceptableOrUnknown(
              data['preferred_tone']!, _preferredToneMeta));
    }
    if (data.containsKey('preferred_pace')) {
      context.handle(
          _preferredPaceMeta,
          preferredPace.isAcceptableOrUnknown(
              data['preferred_pace']!, _preferredPaceMeta));
    }
    if (data.containsKey('preferred_format')) {
      context.handle(
          _preferredFormatMeta,
          preferredFormat.isAcceptableOrUnknown(
              data['preferred_format']!, _preferredFormatMeta));
    }
    if (data.containsKey('support_notes')) {
      context.handle(
          _supportNotesMeta,
          supportNotes.isAcceptableOrUnknown(
              data['support_notes']!, _supportNotesMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StudentPromptProfile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StudentPromptProfile(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      teacherId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}teacher_id'])!,
      courseKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}course_key']),
      studentId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}student_id']),
      gradeLevel: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}grade_level']),
      readingLevel: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}reading_level']),
      preferredLanguage: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}preferred_language']),
      interests: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}interests']),
      preferredTone: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}preferred_tone']),
      preferredPace: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}preferred_pace']),
      preferredFormat: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}preferred_format']),
      supportNotes: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}support_notes']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at']),
    );
  }

  @override
  $StudentPromptProfilesTable createAlias(String alias) {
    return $StudentPromptProfilesTable(attachedDatabase, alias);
  }
}

class StudentPromptProfile extends DataClass
    implements Insertable<StudentPromptProfile> {
  final int id;
  final int teacherId;
  final String? courseKey;
  final int? studentId;
  final String? gradeLevel;
  final String? readingLevel;
  final String? preferredLanguage;
  final String? interests;
  final String? preferredTone;
  final String? preferredPace;
  final String? preferredFormat;
  final String? supportNotes;
  final DateTime createdAt;
  final DateTime? updatedAt;
  const StudentPromptProfile(
      {required this.id,
      required this.teacherId,
      this.courseKey,
      this.studentId,
      this.gradeLevel,
      this.readingLevel,
      this.preferredLanguage,
      this.interests,
      this.preferredTone,
      this.preferredPace,
      this.preferredFormat,
      this.supportNotes,
      required this.createdAt,
      this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['teacher_id'] = Variable<int>(teacherId);
    if (!nullToAbsent || courseKey != null) {
      map['course_key'] = Variable<String>(courseKey);
    }
    if (!nullToAbsent || studentId != null) {
      map['student_id'] = Variable<int>(studentId);
    }
    if (!nullToAbsent || gradeLevel != null) {
      map['grade_level'] = Variable<String>(gradeLevel);
    }
    if (!nullToAbsent || readingLevel != null) {
      map['reading_level'] = Variable<String>(readingLevel);
    }
    if (!nullToAbsent || preferredLanguage != null) {
      map['preferred_language'] = Variable<String>(preferredLanguage);
    }
    if (!nullToAbsent || interests != null) {
      map['interests'] = Variable<String>(interests);
    }
    if (!nullToAbsent || preferredTone != null) {
      map['preferred_tone'] = Variable<String>(preferredTone);
    }
    if (!nullToAbsent || preferredPace != null) {
      map['preferred_pace'] = Variable<String>(preferredPace);
    }
    if (!nullToAbsent || preferredFormat != null) {
      map['preferred_format'] = Variable<String>(preferredFormat);
    }
    if (!nullToAbsent || supportNotes != null) {
      map['support_notes'] = Variable<String>(supportNotes);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    return map;
  }

  StudentPromptProfilesCompanion toCompanion(bool nullToAbsent) {
    return StudentPromptProfilesCompanion(
      id: Value(id),
      teacherId: Value(teacherId),
      courseKey: courseKey == null && nullToAbsent
          ? const Value.absent()
          : Value(courseKey),
      studentId: studentId == null && nullToAbsent
          ? const Value.absent()
          : Value(studentId),
      gradeLevel: gradeLevel == null && nullToAbsent
          ? const Value.absent()
          : Value(gradeLevel),
      readingLevel: readingLevel == null && nullToAbsent
          ? const Value.absent()
          : Value(readingLevel),
      preferredLanguage: preferredLanguage == null && nullToAbsent
          ? const Value.absent()
          : Value(preferredLanguage),
      interests: interests == null && nullToAbsent
          ? const Value.absent()
          : Value(interests),
      preferredTone: preferredTone == null && nullToAbsent
          ? const Value.absent()
          : Value(preferredTone),
      preferredPace: preferredPace == null && nullToAbsent
          ? const Value.absent()
          : Value(preferredPace),
      preferredFormat: preferredFormat == null && nullToAbsent
          ? const Value.absent()
          : Value(preferredFormat),
      supportNotes: supportNotes == null && nullToAbsent
          ? const Value.absent()
          : Value(supportNotes),
      createdAt: Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory StudentPromptProfile.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StudentPromptProfile(
      id: serializer.fromJson<int>(json['id']),
      teacherId: serializer.fromJson<int>(json['teacherId']),
      courseKey: serializer.fromJson<String?>(json['courseKey']),
      studentId: serializer.fromJson<int?>(json['studentId']),
      gradeLevel: serializer.fromJson<String?>(json['gradeLevel']),
      readingLevel: serializer.fromJson<String?>(json['readingLevel']),
      preferredLanguage:
          serializer.fromJson<String?>(json['preferredLanguage']),
      interests: serializer.fromJson<String?>(json['interests']),
      preferredTone: serializer.fromJson<String?>(json['preferredTone']),
      preferredPace: serializer.fromJson<String?>(json['preferredPace']),
      preferredFormat: serializer.fromJson<String?>(json['preferredFormat']),
      supportNotes: serializer.fromJson<String?>(json['supportNotes']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'teacherId': serializer.toJson<int>(teacherId),
      'courseKey': serializer.toJson<String?>(courseKey),
      'studentId': serializer.toJson<int?>(studentId),
      'gradeLevel': serializer.toJson<String?>(gradeLevel),
      'readingLevel': serializer.toJson<String?>(readingLevel),
      'preferredLanguage': serializer.toJson<String?>(preferredLanguage),
      'interests': serializer.toJson<String?>(interests),
      'preferredTone': serializer.toJson<String?>(preferredTone),
      'preferredPace': serializer.toJson<String?>(preferredPace),
      'preferredFormat': serializer.toJson<String?>(preferredFormat),
      'supportNotes': serializer.toJson<String?>(supportNotes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
    };
  }

  StudentPromptProfile copyWith(
          {int? id,
          int? teacherId,
          Value<String?> courseKey = const Value.absent(),
          Value<int?> studentId = const Value.absent(),
          Value<String?> gradeLevel = const Value.absent(),
          Value<String?> readingLevel = const Value.absent(),
          Value<String?> preferredLanguage = const Value.absent(),
          Value<String?> interests = const Value.absent(),
          Value<String?> preferredTone = const Value.absent(),
          Value<String?> preferredPace = const Value.absent(),
          Value<String?> preferredFormat = const Value.absent(),
          Value<String?> supportNotes = const Value.absent(),
          DateTime? createdAt,
          Value<DateTime?> updatedAt = const Value.absent()}) =>
      StudentPromptProfile(
        id: id ?? this.id,
        teacherId: teacherId ?? this.teacherId,
        courseKey: courseKey.present ? courseKey.value : this.courseKey,
        studentId: studentId.present ? studentId.value : this.studentId,
        gradeLevel: gradeLevel.present ? gradeLevel.value : this.gradeLevel,
        readingLevel:
            readingLevel.present ? readingLevel.value : this.readingLevel,
        preferredLanguage: preferredLanguage.present
            ? preferredLanguage.value
            : this.preferredLanguage,
        interests: interests.present ? interests.value : this.interests,
        preferredTone:
            preferredTone.present ? preferredTone.value : this.preferredTone,
        preferredPace:
            preferredPace.present ? preferredPace.value : this.preferredPace,
        preferredFormat: preferredFormat.present
            ? preferredFormat.value
            : this.preferredFormat,
        supportNotes:
            supportNotes.present ? supportNotes.value : this.supportNotes,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
      );
  StudentPromptProfile copyWithCompanion(StudentPromptProfilesCompanion data) {
    return StudentPromptProfile(
      id: data.id.present ? data.id.value : this.id,
      teacherId: data.teacherId.present ? data.teacherId.value : this.teacherId,
      courseKey: data.courseKey.present ? data.courseKey.value : this.courseKey,
      studentId: data.studentId.present ? data.studentId.value : this.studentId,
      gradeLevel:
          data.gradeLevel.present ? data.gradeLevel.value : this.gradeLevel,
      readingLevel: data.readingLevel.present
          ? data.readingLevel.value
          : this.readingLevel,
      preferredLanguage: data.preferredLanguage.present
          ? data.preferredLanguage.value
          : this.preferredLanguage,
      interests: data.interests.present ? data.interests.value : this.interests,
      preferredTone: data.preferredTone.present
          ? data.preferredTone.value
          : this.preferredTone,
      preferredPace: data.preferredPace.present
          ? data.preferredPace.value
          : this.preferredPace,
      preferredFormat: data.preferredFormat.present
          ? data.preferredFormat.value
          : this.preferredFormat,
      supportNotes: data.supportNotes.present
          ? data.supportNotes.value
          : this.supportNotes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StudentPromptProfile(')
          ..write('id: $id, ')
          ..write('teacherId: $teacherId, ')
          ..write('courseKey: $courseKey, ')
          ..write('studentId: $studentId, ')
          ..write('gradeLevel: $gradeLevel, ')
          ..write('readingLevel: $readingLevel, ')
          ..write('preferredLanguage: $preferredLanguage, ')
          ..write('interests: $interests, ')
          ..write('preferredTone: $preferredTone, ')
          ..write('preferredPace: $preferredPace, ')
          ..write('preferredFormat: $preferredFormat, ')
          ..write('supportNotes: $supportNotes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      teacherId,
      courseKey,
      studentId,
      gradeLevel,
      readingLevel,
      preferredLanguage,
      interests,
      preferredTone,
      preferredPace,
      preferredFormat,
      supportNotes,
      createdAt,
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StudentPromptProfile &&
          other.id == this.id &&
          other.teacherId == this.teacherId &&
          other.courseKey == this.courseKey &&
          other.studentId == this.studentId &&
          other.gradeLevel == this.gradeLevel &&
          other.readingLevel == this.readingLevel &&
          other.preferredLanguage == this.preferredLanguage &&
          other.interests == this.interests &&
          other.preferredTone == this.preferredTone &&
          other.preferredPace == this.preferredPace &&
          other.preferredFormat == this.preferredFormat &&
          other.supportNotes == this.supportNotes &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class StudentPromptProfilesCompanion
    extends UpdateCompanion<StudentPromptProfile> {
  final Value<int> id;
  final Value<int> teacherId;
  final Value<String?> courseKey;
  final Value<int?> studentId;
  final Value<String?> gradeLevel;
  final Value<String?> readingLevel;
  final Value<String?> preferredLanguage;
  final Value<String?> interests;
  final Value<String?> preferredTone;
  final Value<String?> preferredPace;
  final Value<String?> preferredFormat;
  final Value<String?> supportNotes;
  final Value<DateTime> createdAt;
  final Value<DateTime?> updatedAt;
  const StudentPromptProfilesCompanion({
    this.id = const Value.absent(),
    this.teacherId = const Value.absent(),
    this.courseKey = const Value.absent(),
    this.studentId = const Value.absent(),
    this.gradeLevel = const Value.absent(),
    this.readingLevel = const Value.absent(),
    this.preferredLanguage = const Value.absent(),
    this.interests = const Value.absent(),
    this.preferredTone = const Value.absent(),
    this.preferredPace = const Value.absent(),
    this.preferredFormat = const Value.absent(),
    this.supportNotes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  StudentPromptProfilesCompanion.insert({
    this.id = const Value.absent(),
    required int teacherId,
    this.courseKey = const Value.absent(),
    this.studentId = const Value.absent(),
    this.gradeLevel = const Value.absent(),
    this.readingLevel = const Value.absent(),
    this.preferredLanguage = const Value.absent(),
    this.interests = const Value.absent(),
    this.preferredTone = const Value.absent(),
    this.preferredPace = const Value.absent(),
    this.preferredFormat = const Value.absent(),
    this.supportNotes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : teacherId = Value(teacherId);
  static Insertable<StudentPromptProfile> custom({
    Expression<int>? id,
    Expression<int>? teacherId,
    Expression<String>? courseKey,
    Expression<int>? studentId,
    Expression<String>? gradeLevel,
    Expression<String>? readingLevel,
    Expression<String>? preferredLanguage,
    Expression<String>? interests,
    Expression<String>? preferredTone,
    Expression<String>? preferredPace,
    Expression<String>? preferredFormat,
    Expression<String>? supportNotes,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (teacherId != null) 'teacher_id': teacherId,
      if (courseKey != null) 'course_key': courseKey,
      if (studentId != null) 'student_id': studentId,
      if (gradeLevel != null) 'grade_level': gradeLevel,
      if (readingLevel != null) 'reading_level': readingLevel,
      if (preferredLanguage != null) 'preferred_language': preferredLanguage,
      if (interests != null) 'interests': interests,
      if (preferredTone != null) 'preferred_tone': preferredTone,
      if (preferredPace != null) 'preferred_pace': preferredPace,
      if (preferredFormat != null) 'preferred_format': preferredFormat,
      if (supportNotes != null) 'support_notes': supportNotes,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  StudentPromptProfilesCompanion copyWith(
      {Value<int>? id,
      Value<int>? teacherId,
      Value<String?>? courseKey,
      Value<int?>? studentId,
      Value<String?>? gradeLevel,
      Value<String?>? readingLevel,
      Value<String?>? preferredLanguage,
      Value<String?>? interests,
      Value<String?>? preferredTone,
      Value<String?>? preferredPace,
      Value<String?>? preferredFormat,
      Value<String?>? supportNotes,
      Value<DateTime>? createdAt,
      Value<DateTime?>? updatedAt}) {
    return StudentPromptProfilesCompanion(
      id: id ?? this.id,
      teacherId: teacherId ?? this.teacherId,
      courseKey: courseKey ?? this.courseKey,
      studentId: studentId ?? this.studentId,
      gradeLevel: gradeLevel ?? this.gradeLevel,
      readingLevel: readingLevel ?? this.readingLevel,
      preferredLanguage: preferredLanguage ?? this.preferredLanguage,
      interests: interests ?? this.interests,
      preferredTone: preferredTone ?? this.preferredTone,
      preferredPace: preferredPace ?? this.preferredPace,
      preferredFormat: preferredFormat ?? this.preferredFormat,
      supportNotes: supportNotes ?? this.supportNotes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (teacherId.present) {
      map['teacher_id'] = Variable<int>(teacherId.value);
    }
    if (courseKey.present) {
      map['course_key'] = Variable<String>(courseKey.value);
    }
    if (studentId.present) {
      map['student_id'] = Variable<int>(studentId.value);
    }
    if (gradeLevel.present) {
      map['grade_level'] = Variable<String>(gradeLevel.value);
    }
    if (readingLevel.present) {
      map['reading_level'] = Variable<String>(readingLevel.value);
    }
    if (preferredLanguage.present) {
      map['preferred_language'] = Variable<String>(preferredLanguage.value);
    }
    if (interests.present) {
      map['interests'] = Variable<String>(interests.value);
    }
    if (preferredTone.present) {
      map['preferred_tone'] = Variable<String>(preferredTone.value);
    }
    if (preferredPace.present) {
      map['preferred_pace'] = Variable<String>(preferredPace.value);
    }
    if (preferredFormat.present) {
      map['preferred_format'] = Variable<String>(preferredFormat.value);
    }
    if (supportNotes.present) {
      map['support_notes'] = Variable<String>(supportNotes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StudentPromptProfilesCompanion(')
          ..write('id: $id, ')
          ..write('teacherId: $teacherId, ')
          ..write('courseKey: $courseKey, ')
          ..write('studentId: $studentId, ')
          ..write('gradeLevel: $gradeLevel, ')
          ..write('readingLevel: $readingLevel, ')
          ..write('preferredLanguage: $preferredLanguage, ')
          ..write('interests: $interests, ')
          ..write('preferredTone: $preferredTone, ')
          ..write('preferredPace: $preferredPace, ')
          ..write('preferredFormat: $preferredFormat, ')
          ..write('supportNotes: $supportNotes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $CourseRemoteLinksTable extends CourseRemoteLinks
    with TableInfo<$CourseRemoteLinksTable, CourseRemoteLink> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CourseRemoteLinksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _courseVersionIdMeta =
      const VerificationMeta('courseVersionId');
  @override
  late final GeneratedColumn<int> courseVersionId = GeneratedColumn<int>(
      'course_version_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _remoteCourseIdMeta =
      const VerificationMeta('remoteCourseId');
  @override
  late final GeneratedColumn<int> remoteCourseId = GeneratedColumn<int>(
      'remote_course_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns =>
      [id, courseVersionId, remoteCourseId, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'course_remote_links';
  @override
  VerificationContext validateIntegrity(Insertable<CourseRemoteLink> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('course_version_id')) {
      context.handle(
          _courseVersionIdMeta,
          courseVersionId.isAcceptableOrUnknown(
              data['course_version_id']!, _courseVersionIdMeta));
    } else if (isInserting) {
      context.missing(_courseVersionIdMeta);
    }
    if (data.containsKey('remote_course_id')) {
      context.handle(
          _remoteCourseIdMeta,
          remoteCourseId.isAcceptableOrUnknown(
              data['remote_course_id']!, _remoteCourseIdMeta));
    } else if (isInserting) {
      context.missing(_remoteCourseIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
        {courseVersionId},
        {remoteCourseId},
      ];
  @override
  CourseRemoteLink map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CourseRemoteLink(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      courseVersionId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}course_version_id'])!,
      remoteCourseId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}remote_course_id'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $CourseRemoteLinksTable createAlias(String alias) {
    return $CourseRemoteLinksTable(attachedDatabase, alias);
  }
}

class CourseRemoteLink extends DataClass
    implements Insertable<CourseRemoteLink> {
  final int id;
  final int courseVersionId;
  final int remoteCourseId;
  final DateTime createdAt;
  const CourseRemoteLink(
      {required this.id,
      required this.courseVersionId,
      required this.remoteCourseId,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['course_version_id'] = Variable<int>(courseVersionId);
    map['remote_course_id'] = Variable<int>(remoteCourseId);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  CourseRemoteLinksCompanion toCompanion(bool nullToAbsent) {
    return CourseRemoteLinksCompanion(
      id: Value(id),
      courseVersionId: Value(courseVersionId),
      remoteCourseId: Value(remoteCourseId),
      createdAt: Value(createdAt),
    );
  }

  factory CourseRemoteLink.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CourseRemoteLink(
      id: serializer.fromJson<int>(json['id']),
      courseVersionId: serializer.fromJson<int>(json['courseVersionId']),
      remoteCourseId: serializer.fromJson<int>(json['remoteCourseId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'courseVersionId': serializer.toJson<int>(courseVersionId),
      'remoteCourseId': serializer.toJson<int>(remoteCourseId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  CourseRemoteLink copyWith(
          {int? id,
          int? courseVersionId,
          int? remoteCourseId,
          DateTime? createdAt}) =>
      CourseRemoteLink(
        id: id ?? this.id,
        courseVersionId: courseVersionId ?? this.courseVersionId,
        remoteCourseId: remoteCourseId ?? this.remoteCourseId,
        createdAt: createdAt ?? this.createdAt,
      );
  CourseRemoteLink copyWithCompanion(CourseRemoteLinksCompanion data) {
    return CourseRemoteLink(
      id: data.id.present ? data.id.value : this.id,
      courseVersionId: data.courseVersionId.present
          ? data.courseVersionId.value
          : this.courseVersionId,
      remoteCourseId: data.remoteCourseId.present
          ? data.remoteCourseId.value
          : this.remoteCourseId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CourseRemoteLink(')
          ..write('id: $id, ')
          ..write('courseVersionId: $courseVersionId, ')
          ..write('remoteCourseId: $remoteCourseId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, courseVersionId, remoteCourseId, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CourseRemoteLink &&
          other.id == this.id &&
          other.courseVersionId == this.courseVersionId &&
          other.remoteCourseId == this.remoteCourseId &&
          other.createdAt == this.createdAt);
}

class CourseRemoteLinksCompanion extends UpdateCompanion<CourseRemoteLink> {
  final Value<int> id;
  final Value<int> courseVersionId;
  final Value<int> remoteCourseId;
  final Value<DateTime> createdAt;
  const CourseRemoteLinksCompanion({
    this.id = const Value.absent(),
    this.courseVersionId = const Value.absent(),
    this.remoteCourseId = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  CourseRemoteLinksCompanion.insert({
    this.id = const Value.absent(),
    required int courseVersionId,
    required int remoteCourseId,
    this.createdAt = const Value.absent(),
  })  : courseVersionId = Value(courseVersionId),
        remoteCourseId = Value(remoteCourseId);
  static Insertable<CourseRemoteLink> custom({
    Expression<int>? id,
    Expression<int>? courseVersionId,
    Expression<int>? remoteCourseId,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (courseVersionId != null) 'course_version_id': courseVersionId,
      if (remoteCourseId != null) 'remote_course_id': remoteCourseId,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  CourseRemoteLinksCompanion copyWith(
      {Value<int>? id,
      Value<int>? courseVersionId,
      Value<int>? remoteCourseId,
      Value<DateTime>? createdAt}) {
    return CourseRemoteLinksCompanion(
      id: id ?? this.id,
      courseVersionId: courseVersionId ?? this.courseVersionId,
      remoteCourseId: remoteCourseId ?? this.remoteCourseId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (courseVersionId.present) {
      map['course_version_id'] = Variable<int>(courseVersionId.value);
    }
    if (remoteCourseId.present) {
      map['remote_course_id'] = Variable<int>(remoteCourseId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CourseRemoteLinksCompanion(')
          ..write('id: $id, ')
          ..write('courseVersionId: $courseVersionId, ')
          ..write('remoteCourseId: $remoteCourseId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $SyncItemStatesTable extends SyncItemStates
    with TableInfo<$SyncItemStatesTable, SyncItemState> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncItemStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _remoteUserIdMeta =
      const VerificationMeta('remoteUserId');
  @override
  late final GeneratedColumn<int> remoteUserId = GeneratedColumn<int>(
      'remote_user_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _domainMeta = const VerificationMeta('domain');
  @override
  late final GeneratedColumn<String> domain = GeneratedColumn<String>(
      'domain', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _scopeKeyMeta =
      const VerificationMeta('scopeKey');
  @override
  late final GeneratedColumn<String> scopeKey = GeneratedColumn<String>(
      'scope_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _contentHashMeta =
      const VerificationMeta('contentHash');
  @override
  late final GeneratedColumn<String> contentHash = GeneratedColumn<String>(
      'content_hash', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _lastChangedAtMeta =
      const VerificationMeta('lastChangedAt');
  @override
  late final GeneratedColumn<DateTime> lastChangedAt =
      GeneratedColumn<DateTime>('last_changed_at', aliasedName, false,
          type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _lastSyncedAtMeta =
      const VerificationMeta('lastSyncedAt');
  @override
  late final GeneratedColumn<DateTime> lastSyncedAt = GeneratedColumn<DateTime>(
      'last_synced_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        remoteUserId,
        domain,
        scopeKey,
        contentHash,
        lastChangedAt,
        lastSyncedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_item_states';
  @override
  VerificationContext validateIntegrity(Insertable<SyncItemState> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('remote_user_id')) {
      context.handle(
          _remoteUserIdMeta,
          remoteUserId.isAcceptableOrUnknown(
              data['remote_user_id']!, _remoteUserIdMeta));
    } else if (isInserting) {
      context.missing(_remoteUserIdMeta);
    }
    if (data.containsKey('domain')) {
      context.handle(_domainMeta,
          domain.isAcceptableOrUnknown(data['domain']!, _domainMeta));
    } else if (isInserting) {
      context.missing(_domainMeta);
    }
    if (data.containsKey('scope_key')) {
      context.handle(_scopeKeyMeta,
          scopeKey.isAcceptableOrUnknown(data['scope_key']!, _scopeKeyMeta));
    } else if (isInserting) {
      context.missing(_scopeKeyMeta);
    }
    if (data.containsKey('content_hash')) {
      context.handle(
          _contentHashMeta,
          contentHash.isAcceptableOrUnknown(
              data['content_hash']!, _contentHashMeta));
    } else if (isInserting) {
      context.missing(_contentHashMeta);
    }
    if (data.containsKey('last_changed_at')) {
      context.handle(
          _lastChangedAtMeta,
          lastChangedAt.isAcceptableOrUnknown(
              data['last_changed_at']!, _lastChangedAtMeta));
    } else if (isInserting) {
      context.missing(_lastChangedAtMeta);
    }
    if (data.containsKey('last_synced_at')) {
      context.handle(
          _lastSyncedAtMeta,
          lastSyncedAt.isAcceptableOrUnknown(
              data['last_synced_at']!, _lastSyncedAtMeta));
    } else if (isInserting) {
      context.missing(_lastSyncedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {remoteUserId, domain, scopeKey};
  @override
  SyncItemState map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncItemState(
      remoteUserId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}remote_user_id'])!,
      domain: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}domain'])!,
      scopeKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}scope_key'])!,
      contentHash: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content_hash'])!,
      lastChangedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_changed_at'])!,
      lastSyncedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_synced_at'])!,
    );
  }

  @override
  $SyncItemStatesTable createAlias(String alias) {
    return $SyncItemStatesTable(attachedDatabase, alias);
  }
}

class SyncItemState extends DataClass implements Insertable<SyncItemState> {
  final int remoteUserId;
  final String domain;
  final String scopeKey;
  final String contentHash;
  final DateTime lastChangedAt;
  final DateTime lastSyncedAt;
  const SyncItemState(
      {required this.remoteUserId,
      required this.domain,
      required this.scopeKey,
      required this.contentHash,
      required this.lastChangedAt,
      required this.lastSyncedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['remote_user_id'] = Variable<int>(remoteUserId);
    map['domain'] = Variable<String>(domain);
    map['scope_key'] = Variable<String>(scopeKey);
    map['content_hash'] = Variable<String>(contentHash);
    map['last_changed_at'] = Variable<DateTime>(lastChangedAt);
    map['last_synced_at'] = Variable<DateTime>(lastSyncedAt);
    return map;
  }

  SyncItemStatesCompanion toCompanion(bool nullToAbsent) {
    return SyncItemStatesCompanion(
      remoteUserId: Value(remoteUserId),
      domain: Value(domain),
      scopeKey: Value(scopeKey),
      contentHash: Value(contentHash),
      lastChangedAt: Value(lastChangedAt),
      lastSyncedAt: Value(lastSyncedAt),
    );
  }

  factory SyncItemState.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncItemState(
      remoteUserId: serializer.fromJson<int>(json['remoteUserId']),
      domain: serializer.fromJson<String>(json['domain']),
      scopeKey: serializer.fromJson<String>(json['scopeKey']),
      contentHash: serializer.fromJson<String>(json['contentHash']),
      lastChangedAt: serializer.fromJson<DateTime>(json['lastChangedAt']),
      lastSyncedAt: serializer.fromJson<DateTime>(json['lastSyncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'remoteUserId': serializer.toJson<int>(remoteUserId),
      'domain': serializer.toJson<String>(domain),
      'scopeKey': serializer.toJson<String>(scopeKey),
      'contentHash': serializer.toJson<String>(contentHash),
      'lastChangedAt': serializer.toJson<DateTime>(lastChangedAt),
      'lastSyncedAt': serializer.toJson<DateTime>(lastSyncedAt),
    };
  }

  SyncItemState copyWith(
          {int? remoteUserId,
          String? domain,
          String? scopeKey,
          String? contentHash,
          DateTime? lastChangedAt,
          DateTime? lastSyncedAt}) =>
      SyncItemState(
        remoteUserId: remoteUserId ?? this.remoteUserId,
        domain: domain ?? this.domain,
        scopeKey: scopeKey ?? this.scopeKey,
        contentHash: contentHash ?? this.contentHash,
        lastChangedAt: lastChangedAt ?? this.lastChangedAt,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      );
  SyncItemState copyWithCompanion(SyncItemStatesCompanion data) {
    return SyncItemState(
      remoteUserId: data.remoteUserId.present
          ? data.remoteUserId.value
          : this.remoteUserId,
      domain: data.domain.present ? data.domain.value : this.domain,
      scopeKey: data.scopeKey.present ? data.scopeKey.value : this.scopeKey,
      contentHash:
          data.contentHash.present ? data.contentHash.value : this.contentHash,
      lastChangedAt: data.lastChangedAt.present
          ? data.lastChangedAt.value
          : this.lastChangedAt,
      lastSyncedAt: data.lastSyncedAt.present
          ? data.lastSyncedAt.value
          : this.lastSyncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncItemState(')
          ..write('remoteUserId: $remoteUserId, ')
          ..write('domain: $domain, ')
          ..write('scopeKey: $scopeKey, ')
          ..write('contentHash: $contentHash, ')
          ..write('lastChangedAt: $lastChangedAt, ')
          ..write('lastSyncedAt: $lastSyncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      remoteUserId, domain, scopeKey, contentHash, lastChangedAt, lastSyncedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncItemState &&
          other.remoteUserId == this.remoteUserId &&
          other.domain == this.domain &&
          other.scopeKey == this.scopeKey &&
          other.contentHash == this.contentHash &&
          other.lastChangedAt == this.lastChangedAt &&
          other.lastSyncedAt == this.lastSyncedAt);
}

class SyncItemStatesCompanion extends UpdateCompanion<SyncItemState> {
  final Value<int> remoteUserId;
  final Value<String> domain;
  final Value<String> scopeKey;
  final Value<String> contentHash;
  final Value<DateTime> lastChangedAt;
  final Value<DateTime> lastSyncedAt;
  final Value<int> rowid;
  const SyncItemStatesCompanion({
    this.remoteUserId = const Value.absent(),
    this.domain = const Value.absent(),
    this.scopeKey = const Value.absent(),
    this.contentHash = const Value.absent(),
    this.lastChangedAt = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncItemStatesCompanion.insert({
    required int remoteUserId,
    required String domain,
    required String scopeKey,
    required String contentHash,
    required DateTime lastChangedAt,
    required DateTime lastSyncedAt,
    this.rowid = const Value.absent(),
  })  : remoteUserId = Value(remoteUserId),
        domain = Value(domain),
        scopeKey = Value(scopeKey),
        contentHash = Value(contentHash),
        lastChangedAt = Value(lastChangedAt),
        lastSyncedAt = Value(lastSyncedAt);
  static Insertable<SyncItemState> custom({
    Expression<int>? remoteUserId,
    Expression<String>? domain,
    Expression<String>? scopeKey,
    Expression<String>? contentHash,
    Expression<DateTime>? lastChangedAt,
    Expression<DateTime>? lastSyncedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (remoteUserId != null) 'remote_user_id': remoteUserId,
      if (domain != null) 'domain': domain,
      if (scopeKey != null) 'scope_key': scopeKey,
      if (contentHash != null) 'content_hash': contentHash,
      if (lastChangedAt != null) 'last_changed_at': lastChangedAt,
      if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncItemStatesCompanion copyWith(
      {Value<int>? remoteUserId,
      Value<String>? domain,
      Value<String>? scopeKey,
      Value<String>? contentHash,
      Value<DateTime>? lastChangedAt,
      Value<DateTime>? lastSyncedAt,
      Value<int>? rowid}) {
    return SyncItemStatesCompanion(
      remoteUserId: remoteUserId ?? this.remoteUserId,
      domain: domain ?? this.domain,
      scopeKey: scopeKey ?? this.scopeKey,
      contentHash: contentHash ?? this.contentHash,
      lastChangedAt: lastChangedAt ?? this.lastChangedAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (remoteUserId.present) {
      map['remote_user_id'] = Variable<int>(remoteUserId.value);
    }
    if (domain.present) {
      map['domain'] = Variable<String>(domain.value);
    }
    if (scopeKey.present) {
      map['scope_key'] = Variable<String>(scopeKey.value);
    }
    if (contentHash.present) {
      map['content_hash'] = Variable<String>(contentHash.value);
    }
    if (lastChangedAt.present) {
      map['last_changed_at'] = Variable<DateTime>(lastChangedAt.value);
    }
    if (lastSyncedAt.present) {
      map['last_synced_at'] = Variable<DateTime>(lastSyncedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncItemStatesCompanion(')
          ..write('remoteUserId: $remoteUserId, ')
          ..write('domain: $domain, ')
          ..write('scopeKey: $scopeKey, ')
          ..write('contentHash: $contentHash, ')
          ..write('lastChangedAt: $lastChangedAt, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncMetadataEntriesTable extends SyncMetadataEntries
    with TableInfo<$SyncMetadataEntriesTable, SyncMetadataEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncMetadataEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _remoteUserIdMeta =
      const VerificationMeta('remoteUserId');
  @override
  late final GeneratedColumn<int> remoteUserId = GeneratedColumn<int>(
      'remote_user_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
      'kind', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _domainMeta = const VerificationMeta('domain');
  @override
  late final GeneratedColumn<String> domain = GeneratedColumn<String>(
      'domain', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _scopeKeyMeta =
      const VerificationMeta('scopeKey');
  @override
  late final GeneratedColumn<String> scopeKey = GeneratedColumn<String>(
      'scope_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
      'value', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns =>
      [remoteUserId, kind, domain, scopeKey, value, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_metadata_entries';
  @override
  VerificationContext validateIntegrity(Insertable<SyncMetadataEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('remote_user_id')) {
      context.handle(
          _remoteUserIdMeta,
          remoteUserId.isAcceptableOrUnknown(
              data['remote_user_id']!, _remoteUserIdMeta));
    } else if (isInserting) {
      context.missing(_remoteUserIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
          _kindMeta, kind.isAcceptableOrUnknown(data['kind']!, _kindMeta));
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('domain')) {
      context.handle(_domainMeta,
          domain.isAcceptableOrUnknown(data['domain']!, _domainMeta));
    } else if (isInserting) {
      context.missing(_domainMeta);
    }
    if (data.containsKey('scope_key')) {
      context.handle(_scopeKeyMeta,
          scopeKey.isAcceptableOrUnknown(data['scope_key']!, _scopeKeyMeta));
    } else if (isInserting) {
      context.missing(_scopeKeyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
          _valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey =>
      {remoteUserId, kind, domain, scopeKey};
  @override
  SyncMetadataEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncMetadataEntry(
      remoteUserId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}remote_user_id'])!,
      kind: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}kind'])!,
      domain: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}domain'])!,
      scopeKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}scope_key'])!,
      value: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $SyncMetadataEntriesTable createAlias(String alias) {
    return $SyncMetadataEntriesTable(attachedDatabase, alias);
  }
}

class SyncMetadataEntry extends DataClass
    implements Insertable<SyncMetadataEntry> {
  final int remoteUserId;
  final String kind;
  final String domain;
  final String scopeKey;
  final String value;
  final DateTime updatedAt;
  const SyncMetadataEntry(
      {required this.remoteUserId,
      required this.kind,
      required this.domain,
      required this.scopeKey,
      required this.value,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['remote_user_id'] = Variable<int>(remoteUserId);
    map['kind'] = Variable<String>(kind);
    map['domain'] = Variable<String>(domain);
    map['scope_key'] = Variable<String>(scopeKey);
    map['value'] = Variable<String>(value);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SyncMetadataEntriesCompanion toCompanion(bool nullToAbsent) {
    return SyncMetadataEntriesCompanion(
      remoteUserId: Value(remoteUserId),
      kind: Value(kind),
      domain: Value(domain),
      scopeKey: Value(scopeKey),
      value: Value(value),
      updatedAt: Value(updatedAt),
    );
  }

  factory SyncMetadataEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncMetadataEntry(
      remoteUserId: serializer.fromJson<int>(json['remoteUserId']),
      kind: serializer.fromJson<String>(json['kind']),
      domain: serializer.fromJson<String>(json['domain']),
      scopeKey: serializer.fromJson<String>(json['scopeKey']),
      value: serializer.fromJson<String>(json['value']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'remoteUserId': serializer.toJson<int>(remoteUserId),
      'kind': serializer.toJson<String>(kind),
      'domain': serializer.toJson<String>(domain),
      'scopeKey': serializer.toJson<String>(scopeKey),
      'value': serializer.toJson<String>(value),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SyncMetadataEntry copyWith(
          {int? remoteUserId,
          String? kind,
          String? domain,
          String? scopeKey,
          String? value,
          DateTime? updatedAt}) =>
      SyncMetadataEntry(
        remoteUserId: remoteUserId ?? this.remoteUserId,
        kind: kind ?? this.kind,
        domain: domain ?? this.domain,
        scopeKey: scopeKey ?? this.scopeKey,
        value: value ?? this.value,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  SyncMetadataEntry copyWithCompanion(SyncMetadataEntriesCompanion data) {
    return SyncMetadataEntry(
      remoteUserId: data.remoteUserId.present
          ? data.remoteUserId.value
          : this.remoteUserId,
      kind: data.kind.present ? data.kind.value : this.kind,
      domain: data.domain.present ? data.domain.value : this.domain,
      scopeKey: data.scopeKey.present ? data.scopeKey.value : this.scopeKey,
      value: data.value.present ? data.value.value : this.value,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetadataEntry(')
          ..write('remoteUserId: $remoteUserId, ')
          ..write('kind: $kind, ')
          ..write('domain: $domain, ')
          ..write('scopeKey: $scopeKey, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(remoteUserId, kind, domain, scopeKey, value, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncMetadataEntry &&
          other.remoteUserId == this.remoteUserId &&
          other.kind == this.kind &&
          other.domain == this.domain &&
          other.scopeKey == this.scopeKey &&
          other.value == this.value &&
          other.updatedAt == this.updatedAt);
}

class SyncMetadataEntriesCompanion extends UpdateCompanion<SyncMetadataEntry> {
  final Value<int> remoteUserId;
  final Value<String> kind;
  final Value<String> domain;
  final Value<String> scopeKey;
  final Value<String> value;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SyncMetadataEntriesCompanion({
    this.remoteUserId = const Value.absent(),
    this.kind = const Value.absent(),
    this.domain = const Value.absent(),
    this.scopeKey = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncMetadataEntriesCompanion.insert({
    required int remoteUserId,
    required String kind,
    required String domain,
    required String scopeKey,
    required String value,
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : remoteUserId = Value(remoteUserId),
        kind = Value(kind),
        domain = Value(domain),
        scopeKey = Value(scopeKey),
        value = Value(value);
  static Insertable<SyncMetadataEntry> custom({
    Expression<int>? remoteUserId,
    Expression<String>? kind,
    Expression<String>? domain,
    Expression<String>? scopeKey,
    Expression<String>? value,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (remoteUserId != null) 'remote_user_id': remoteUserId,
      if (kind != null) 'kind': kind,
      if (domain != null) 'domain': domain,
      if (scopeKey != null) 'scope_key': scopeKey,
      if (value != null) 'value': value,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncMetadataEntriesCompanion copyWith(
      {Value<int>? remoteUserId,
      Value<String>? kind,
      Value<String>? domain,
      Value<String>? scopeKey,
      Value<String>? value,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return SyncMetadataEntriesCompanion(
      remoteUserId: remoteUserId ?? this.remoteUserId,
      kind: kind ?? this.kind,
      domain: domain ?? this.domain,
      scopeKey: scopeKey ?? this.scopeKey,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (remoteUserId.present) {
      map['remote_user_id'] = Variable<int>(remoteUserId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (domain.present) {
      map['domain'] = Variable<String>(domain.value);
    }
    if (scopeKey.present) {
      map['scope_key'] = Variable<String>(scopeKey.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetadataEntriesCompanion(')
          ..write('remoteUserId: $remoteUserId, ')
          ..write('kind: $kind, ')
          ..write('domain: $domain, ')
          ..write('scopeKey: $scopeKey, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $UsersTable users = $UsersTable(this);
  late final $CourseVersionsTable courseVersions = $CourseVersionsTable(this);
  late final $CourseNodesTable courseNodes = $CourseNodesTable(this);
  late final $CourseEdgesTable courseEdges = $CourseEdgesTable(this);
  late final $StudentCourseAssignmentsTable studentCourseAssignments =
      $StudentCourseAssignmentsTable(this);
  late final $ProgressEntriesTable progressEntries =
      $ProgressEntriesTable(this);
  late final $ChatSessionsTable chatSessions = $ChatSessionsTable(this);
  late final $ChatMessagesTable chatMessages = $ChatMessagesTable(this);
  late final $LlmCallsTable llmCalls = $LlmCallsTable(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final $ApiConfigsTable apiConfigs = $ApiConfigsTable(this);
  late final $PromptTemplatesTable promptTemplates =
      $PromptTemplatesTable(this);
  late final $StudentPromptProfilesTable studentPromptProfiles =
      $StudentPromptProfilesTable(this);
  late final $CourseRemoteLinksTable courseRemoteLinks =
      $CourseRemoteLinksTable(this);
  late final $SyncItemStatesTable syncItemStates = $SyncItemStatesTable(this);
  late final $SyncMetadataEntriesTable syncMetadataEntries =
      $SyncMetadataEntriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        users,
        courseVersions,
        courseNodes,
        courseEdges,
        studentCourseAssignments,
        progressEntries,
        chatSessions,
        chatMessages,
        llmCalls,
        appSettings,
        apiConfigs,
        promptTemplates,
        studentPromptProfiles,
        courseRemoteLinks,
        syncItemStates,
        syncMetadataEntries
      ];
}

typedef $$UsersTableCreateCompanionBuilder = UsersCompanion Function({
  Value<int> id,
  required String username,
  required String pinHash,
  required String role,
  Value<int?> teacherId,
  Value<int?> remoteUserId,
  Value<DateTime> createdAt,
});
typedef $$UsersTableUpdateCompanionBuilder = UsersCompanion Function({
  Value<int> id,
  Value<String> username,
  Value<String> pinHash,
  Value<String> role,
  Value<int?> teacherId,
  Value<int?> remoteUserId,
  Value<DateTime> createdAt,
});

class $$UsersTableFilterComposer extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get username => $composableBuilder(
      column: $table.username, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get pinHash => $composableBuilder(
      column: $table.pinHash, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get teacherId => $composableBuilder(
      column: $table.teacherId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get remoteUserId => $composableBuilder(
      column: $table.remoteUserId, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$UsersTableOrderingComposer
    extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get username => $composableBuilder(
      column: $table.username, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get pinHash => $composableBuilder(
      column: $table.pinHash, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get teacherId => $composableBuilder(
      column: $table.teacherId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get remoteUserId => $composableBuilder(
      column: $table.remoteUserId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$UsersTableAnnotationComposer
    extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get pinHash =>
      $composableBuilder(column: $table.pinHash, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<int> get teacherId =>
      $composableBuilder(column: $table.teacherId, builder: (column) => column);

  GeneratedColumn<int> get remoteUserId => $composableBuilder(
      column: $table.remoteUserId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$UsersTableTableManager extends RootTableManager<
    _$AppDatabase,
    $UsersTable,
    User,
    $$UsersTableFilterComposer,
    $$UsersTableOrderingComposer,
    $$UsersTableAnnotationComposer,
    $$UsersTableCreateCompanionBuilder,
    $$UsersTableUpdateCompanionBuilder,
    (User, BaseReferences<_$AppDatabase, $UsersTable, User>),
    User,
    PrefetchHooks Function()> {
  $$UsersTableTableManager(_$AppDatabase db, $UsersTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UsersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UsersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UsersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> username = const Value.absent(),
            Value<String> pinHash = const Value.absent(),
            Value<String> role = const Value.absent(),
            Value<int?> teacherId = const Value.absent(),
            Value<int?> remoteUserId = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
          }) =>
              UsersCompanion(
            id: id,
            username: username,
            pinHash: pinHash,
            role: role,
            teacherId: teacherId,
            remoteUserId: remoteUserId,
            createdAt: createdAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String username,
            required String pinHash,
            required String role,
            Value<int?> teacherId = const Value.absent(),
            Value<int?> remoteUserId = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
          }) =>
              UsersCompanion.insert(
            id: id,
            username: username,
            pinHash: pinHash,
            role: role,
            teacherId: teacherId,
            remoteUserId: remoteUserId,
            createdAt: createdAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$UsersTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $UsersTable,
    User,
    $$UsersTableFilterComposer,
    $$UsersTableOrderingComposer,
    $$UsersTableAnnotationComposer,
    $$UsersTableCreateCompanionBuilder,
    $$UsersTableUpdateCompanionBuilder,
    (User, BaseReferences<_$AppDatabase, $UsersTable, User>),
    User,
    PrefetchHooks Function()>;
typedef $$CourseVersionsTableCreateCompanionBuilder = CourseVersionsCompanion
    Function({
  Value<int> id,
  required int teacherId,
  required String subject,
  Value<String?> sourcePath,
  required int granularity,
  required String textbookText,
  Value<String> treeGenStatus,
  Value<String?> treeGenRawResponse,
  Value<bool> treeGenValid,
  Value<String?> treeGenParseError,
  Value<DateTime> createdAt,
  Value<DateTime?> updatedAt,
});
typedef $$CourseVersionsTableUpdateCompanionBuilder = CourseVersionsCompanion
    Function({
  Value<int> id,
  Value<int> teacherId,
  Value<String> subject,
  Value<String?> sourcePath,
  Value<int> granularity,
  Value<String> textbookText,
  Value<String> treeGenStatus,
  Value<String?> treeGenRawResponse,
  Value<bool> treeGenValid,
  Value<String?> treeGenParseError,
  Value<DateTime> createdAt,
  Value<DateTime?> updatedAt,
});

class $$CourseVersionsTableFilterComposer
    extends Composer<_$AppDatabase, $CourseVersionsTable> {
  $$CourseVersionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get teacherId => $composableBuilder(
      column: $table.teacherId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get subject => $composableBuilder(
      column: $table.subject, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sourcePath => $composableBuilder(
      column: $table.sourcePath, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get granularity => $composableBuilder(
      column: $table.granularity, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get textbookText => $composableBuilder(
      column: $table.textbookText, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get treeGenStatus => $composableBuilder(
      column: $table.treeGenStatus, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get treeGenRawResponse => $composableBuilder(
      column: $table.treeGenRawResponse,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get treeGenValid => $composableBuilder(
      column: $table.treeGenValid, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get treeGenParseError => $composableBuilder(
      column: $table.treeGenParseError,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$CourseVersionsTableOrderingComposer
    extends Composer<_$AppDatabase, $CourseVersionsTable> {
  $$CourseVersionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get teacherId => $composableBuilder(
      column: $table.teacherId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get subject => $composableBuilder(
      column: $table.subject, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sourcePath => $composableBuilder(
      column: $table.sourcePath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get granularity => $composableBuilder(
      column: $table.granularity, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get textbookText => $composableBuilder(
      column: $table.textbookText,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get treeGenStatus => $composableBuilder(
      column: $table.treeGenStatus,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get treeGenRawResponse => $composableBuilder(
      column: $table.treeGenRawResponse,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get treeGenValid => $composableBuilder(
      column: $table.treeGenValid,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get treeGenParseError => $composableBuilder(
      column: $table.treeGenParseError,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$CourseVersionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CourseVersionsTable> {
  $$CourseVersionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get teacherId =>
      $composableBuilder(column: $table.teacherId, builder: (column) => column);

  GeneratedColumn<String> get subject =>
      $composableBuilder(column: $table.subject, builder: (column) => column);

  GeneratedColumn<String> get sourcePath => $composableBuilder(
      column: $table.sourcePath, builder: (column) => column);

  GeneratedColumn<int> get granularity => $composableBuilder(
      column: $table.granularity, builder: (column) => column);

  GeneratedColumn<String> get textbookText => $composableBuilder(
      column: $table.textbookText, builder: (column) => column);

  GeneratedColumn<String> get treeGenStatus => $composableBuilder(
      column: $table.treeGenStatus, builder: (column) => column);

  GeneratedColumn<String> get treeGenRawResponse => $composableBuilder(
      column: $table.treeGenRawResponse, builder: (column) => column);

  GeneratedColumn<bool> get treeGenValid => $composableBuilder(
      column: $table.treeGenValid, builder: (column) => column);

  GeneratedColumn<String> get treeGenParseError => $composableBuilder(
      column: $table.treeGenParseError, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CourseVersionsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CourseVersionsTable,
    CourseVersion,
    $$CourseVersionsTableFilterComposer,
    $$CourseVersionsTableOrderingComposer,
    $$CourseVersionsTableAnnotationComposer,
    $$CourseVersionsTableCreateCompanionBuilder,
    $$CourseVersionsTableUpdateCompanionBuilder,
    (
      CourseVersion,
      BaseReferences<_$AppDatabase, $CourseVersionsTable, CourseVersion>
    ),
    CourseVersion,
    PrefetchHooks Function()> {
  $$CourseVersionsTableTableManager(
      _$AppDatabase db, $CourseVersionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CourseVersionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CourseVersionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CourseVersionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> teacherId = const Value.absent(),
            Value<String> subject = const Value.absent(),
            Value<String?> sourcePath = const Value.absent(),
            Value<int> granularity = const Value.absent(),
            Value<String> textbookText = const Value.absent(),
            Value<String> treeGenStatus = const Value.absent(),
            Value<String?> treeGenRawResponse = const Value.absent(),
            Value<bool> treeGenValid = const Value.absent(),
            Value<String?> treeGenParseError = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime?> updatedAt = const Value.absent(),
          }) =>
              CourseVersionsCompanion(
            id: id,
            teacherId: teacherId,
            subject: subject,
            sourcePath: sourcePath,
            granularity: granularity,
            textbookText: textbookText,
            treeGenStatus: treeGenStatus,
            treeGenRawResponse: treeGenRawResponse,
            treeGenValid: treeGenValid,
            treeGenParseError: treeGenParseError,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int teacherId,
            required String subject,
            Value<String?> sourcePath = const Value.absent(),
            required int granularity,
            required String textbookText,
            Value<String> treeGenStatus = const Value.absent(),
            Value<String?> treeGenRawResponse = const Value.absent(),
            Value<bool> treeGenValid = const Value.absent(),
            Value<String?> treeGenParseError = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime?> updatedAt = const Value.absent(),
          }) =>
              CourseVersionsCompanion.insert(
            id: id,
            teacherId: teacherId,
            subject: subject,
            sourcePath: sourcePath,
            granularity: granularity,
            textbookText: textbookText,
            treeGenStatus: treeGenStatus,
            treeGenRawResponse: treeGenRawResponse,
            treeGenValid: treeGenValid,
            treeGenParseError: treeGenParseError,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CourseVersionsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CourseVersionsTable,
    CourseVersion,
    $$CourseVersionsTableFilterComposer,
    $$CourseVersionsTableOrderingComposer,
    $$CourseVersionsTableAnnotationComposer,
    $$CourseVersionsTableCreateCompanionBuilder,
    $$CourseVersionsTableUpdateCompanionBuilder,
    (
      CourseVersion,
      BaseReferences<_$AppDatabase, $CourseVersionsTable, CourseVersion>
    ),
    CourseVersion,
    PrefetchHooks Function()>;
typedef $$CourseNodesTableCreateCompanionBuilder = CourseNodesCompanion
    Function({
  Value<int> id,
  required int courseVersionId,
  required String kpKey,
  required String title,
  required String description,
  required int orderIndex,
});
typedef $$CourseNodesTableUpdateCompanionBuilder = CourseNodesCompanion
    Function({
  Value<int> id,
  Value<int> courseVersionId,
  Value<String> kpKey,
  Value<String> title,
  Value<String> description,
  Value<int> orderIndex,
});

class $$CourseNodesTableFilterComposer
    extends Composer<_$AppDatabase, $CourseNodesTable> {
  $$CourseNodesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get courseVersionId => $composableBuilder(
      column: $table.courseVersionId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get kpKey => $composableBuilder(
      column: $table.kpKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get orderIndex => $composableBuilder(
      column: $table.orderIndex, builder: (column) => ColumnFilters(column));
}

class $$CourseNodesTableOrderingComposer
    extends Composer<_$AppDatabase, $CourseNodesTable> {
  $$CourseNodesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get courseVersionId => $composableBuilder(
      column: $table.courseVersionId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get kpKey => $composableBuilder(
      column: $table.kpKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get orderIndex => $composableBuilder(
      column: $table.orderIndex, builder: (column) => ColumnOrderings(column));
}

class $$CourseNodesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CourseNodesTable> {
  $$CourseNodesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get courseVersionId => $composableBuilder(
      column: $table.courseVersionId, builder: (column) => column);

  GeneratedColumn<String> get kpKey =>
      $composableBuilder(column: $table.kpKey, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<int> get orderIndex => $composableBuilder(
      column: $table.orderIndex, builder: (column) => column);
}

class $$CourseNodesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CourseNodesTable,
    CourseNode,
    $$CourseNodesTableFilterComposer,
    $$CourseNodesTableOrderingComposer,
    $$CourseNodesTableAnnotationComposer,
    $$CourseNodesTableCreateCompanionBuilder,
    $$CourseNodesTableUpdateCompanionBuilder,
    (CourseNode, BaseReferences<_$AppDatabase, $CourseNodesTable, CourseNode>),
    CourseNode,
    PrefetchHooks Function()> {
  $$CourseNodesTableTableManager(_$AppDatabase db, $CourseNodesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CourseNodesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CourseNodesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CourseNodesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> courseVersionId = const Value.absent(),
            Value<String> kpKey = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> description = const Value.absent(),
            Value<int> orderIndex = const Value.absent(),
          }) =>
              CourseNodesCompanion(
            id: id,
            courseVersionId: courseVersionId,
            kpKey: kpKey,
            title: title,
            description: description,
            orderIndex: orderIndex,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int courseVersionId,
            required String kpKey,
            required String title,
            required String description,
            required int orderIndex,
          }) =>
              CourseNodesCompanion.insert(
            id: id,
            courseVersionId: courseVersionId,
            kpKey: kpKey,
            title: title,
            description: description,
            orderIndex: orderIndex,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CourseNodesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CourseNodesTable,
    CourseNode,
    $$CourseNodesTableFilterComposer,
    $$CourseNodesTableOrderingComposer,
    $$CourseNodesTableAnnotationComposer,
    $$CourseNodesTableCreateCompanionBuilder,
    $$CourseNodesTableUpdateCompanionBuilder,
    (CourseNode, BaseReferences<_$AppDatabase, $CourseNodesTable, CourseNode>),
    CourseNode,
    PrefetchHooks Function()>;
typedef $$CourseEdgesTableCreateCompanionBuilder = CourseEdgesCompanion
    Function({
  Value<int> id,
  required int courseVersionId,
  required String fromKpKey,
  required String toKpKey,
});
typedef $$CourseEdgesTableUpdateCompanionBuilder = CourseEdgesCompanion
    Function({
  Value<int> id,
  Value<int> courseVersionId,
  Value<String> fromKpKey,
  Value<String> toKpKey,
});

class $$CourseEdgesTableFilterComposer
    extends Composer<_$AppDatabase, $CourseEdgesTable> {
  $$CourseEdgesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get courseVersionId => $composableBuilder(
      column: $table.courseVersionId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get fromKpKey => $composableBuilder(
      column: $table.fromKpKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get toKpKey => $composableBuilder(
      column: $table.toKpKey, builder: (column) => ColumnFilters(column));
}

class $$CourseEdgesTableOrderingComposer
    extends Composer<_$AppDatabase, $CourseEdgesTable> {
  $$CourseEdgesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get courseVersionId => $composableBuilder(
      column: $table.courseVersionId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get fromKpKey => $composableBuilder(
      column: $table.fromKpKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get toKpKey => $composableBuilder(
      column: $table.toKpKey, builder: (column) => ColumnOrderings(column));
}

class $$CourseEdgesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CourseEdgesTable> {
  $$CourseEdgesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get courseVersionId => $composableBuilder(
      column: $table.courseVersionId, builder: (column) => column);

  GeneratedColumn<String> get fromKpKey =>
      $composableBuilder(column: $table.fromKpKey, builder: (column) => column);

  GeneratedColumn<String> get toKpKey =>
      $composableBuilder(column: $table.toKpKey, builder: (column) => column);
}

class $$CourseEdgesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CourseEdgesTable,
    CourseEdge,
    $$CourseEdgesTableFilterComposer,
    $$CourseEdgesTableOrderingComposer,
    $$CourseEdgesTableAnnotationComposer,
    $$CourseEdgesTableCreateCompanionBuilder,
    $$CourseEdgesTableUpdateCompanionBuilder,
    (CourseEdge, BaseReferences<_$AppDatabase, $CourseEdgesTable, CourseEdge>),
    CourseEdge,
    PrefetchHooks Function()> {
  $$CourseEdgesTableTableManager(_$AppDatabase db, $CourseEdgesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CourseEdgesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CourseEdgesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CourseEdgesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> courseVersionId = const Value.absent(),
            Value<String> fromKpKey = const Value.absent(),
            Value<String> toKpKey = const Value.absent(),
          }) =>
              CourseEdgesCompanion(
            id: id,
            courseVersionId: courseVersionId,
            fromKpKey: fromKpKey,
            toKpKey: toKpKey,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int courseVersionId,
            required String fromKpKey,
            required String toKpKey,
          }) =>
              CourseEdgesCompanion.insert(
            id: id,
            courseVersionId: courseVersionId,
            fromKpKey: fromKpKey,
            toKpKey: toKpKey,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CourseEdgesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CourseEdgesTable,
    CourseEdge,
    $$CourseEdgesTableFilterComposer,
    $$CourseEdgesTableOrderingComposer,
    $$CourseEdgesTableAnnotationComposer,
    $$CourseEdgesTableCreateCompanionBuilder,
    $$CourseEdgesTableUpdateCompanionBuilder,
    (CourseEdge, BaseReferences<_$AppDatabase, $CourseEdgesTable, CourseEdge>),
    CourseEdge,
    PrefetchHooks Function()>;
typedef $$StudentCourseAssignmentsTableCreateCompanionBuilder
    = StudentCourseAssignmentsCompanion Function({
  Value<int> id,
  required int studentId,
  required int courseVersionId,
  Value<DateTime> assignedAt,
});
typedef $$StudentCourseAssignmentsTableUpdateCompanionBuilder
    = StudentCourseAssignmentsCompanion Function({
  Value<int> id,
  Value<int> studentId,
  Value<int> courseVersionId,
  Value<DateTime> assignedAt,
});

class $$StudentCourseAssignmentsTableFilterComposer
    extends Composer<_$AppDatabase, $StudentCourseAssignmentsTable> {
  $$StudentCourseAssignmentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get studentId => $composableBuilder(
      column: $table.studentId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get courseVersionId => $composableBuilder(
      column: $table.courseVersionId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get assignedAt => $composableBuilder(
      column: $table.assignedAt, builder: (column) => ColumnFilters(column));
}

class $$StudentCourseAssignmentsTableOrderingComposer
    extends Composer<_$AppDatabase, $StudentCourseAssignmentsTable> {
  $$StudentCourseAssignmentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get studentId => $composableBuilder(
      column: $table.studentId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get courseVersionId => $composableBuilder(
      column: $table.courseVersionId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get assignedAt => $composableBuilder(
      column: $table.assignedAt, builder: (column) => ColumnOrderings(column));
}

class $$StudentCourseAssignmentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $StudentCourseAssignmentsTable> {
  $$StudentCourseAssignmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get studentId =>
      $composableBuilder(column: $table.studentId, builder: (column) => column);

  GeneratedColumn<int> get courseVersionId => $composableBuilder(
      column: $table.courseVersionId, builder: (column) => column);

  GeneratedColumn<DateTime> get assignedAt => $composableBuilder(
      column: $table.assignedAt, builder: (column) => column);
}

class $$StudentCourseAssignmentsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $StudentCourseAssignmentsTable,
    StudentCourseAssignment,
    $$StudentCourseAssignmentsTableFilterComposer,
    $$StudentCourseAssignmentsTableOrderingComposer,
    $$StudentCourseAssignmentsTableAnnotationComposer,
    $$StudentCourseAssignmentsTableCreateCompanionBuilder,
    $$StudentCourseAssignmentsTableUpdateCompanionBuilder,
    (
      StudentCourseAssignment,
      BaseReferences<_$AppDatabase, $StudentCourseAssignmentsTable,
          StudentCourseAssignment>
    ),
    StudentCourseAssignment,
    PrefetchHooks Function()> {
  $$StudentCourseAssignmentsTableTableManager(
      _$AppDatabase db, $StudentCourseAssignmentsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StudentCourseAssignmentsTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$StudentCourseAssignmentsTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StudentCourseAssignmentsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> studentId = const Value.absent(),
            Value<int> courseVersionId = const Value.absent(),
            Value<DateTime> assignedAt = const Value.absent(),
          }) =>
              StudentCourseAssignmentsCompanion(
            id: id,
            studentId: studentId,
            courseVersionId: courseVersionId,
            assignedAt: assignedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int studentId,
            required int courseVersionId,
            Value<DateTime> assignedAt = const Value.absent(),
          }) =>
              StudentCourseAssignmentsCompanion.insert(
            id: id,
            studentId: studentId,
            courseVersionId: courseVersionId,
            assignedAt: assignedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$StudentCourseAssignmentsTableProcessedTableManager
    = ProcessedTableManager<
        _$AppDatabase,
        $StudentCourseAssignmentsTable,
        StudentCourseAssignment,
        $$StudentCourseAssignmentsTableFilterComposer,
        $$StudentCourseAssignmentsTableOrderingComposer,
        $$StudentCourseAssignmentsTableAnnotationComposer,
        $$StudentCourseAssignmentsTableCreateCompanionBuilder,
        $$StudentCourseAssignmentsTableUpdateCompanionBuilder,
        (
          StudentCourseAssignment,
          BaseReferences<_$AppDatabase, $StudentCourseAssignmentsTable,
              StudentCourseAssignment>
        ),
        StudentCourseAssignment,
        PrefetchHooks Function()>;
typedef $$ProgressEntriesTableCreateCompanionBuilder = ProgressEntriesCompanion
    Function({
  Value<int> id,
  required int studentId,
  required int courseVersionId,
  required String kpKey,
  Value<bool> lit,
  Value<int> litPercent,
  Value<String?> questionLevel,
  Value<String?> summaryText,
  Value<String?> summaryRawResponse,
  Value<bool?> summaryValid,
  Value<DateTime> updatedAt,
});
typedef $$ProgressEntriesTableUpdateCompanionBuilder = ProgressEntriesCompanion
    Function({
  Value<int> id,
  Value<int> studentId,
  Value<int> courseVersionId,
  Value<String> kpKey,
  Value<bool> lit,
  Value<int> litPercent,
  Value<String?> questionLevel,
  Value<String?> summaryText,
  Value<String?> summaryRawResponse,
  Value<bool?> summaryValid,
  Value<DateTime> updatedAt,
});

class $$ProgressEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $ProgressEntriesTable> {
  $$ProgressEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get studentId => $composableBuilder(
      column: $table.studentId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get courseVersionId => $composableBuilder(
      column: $table.courseVersionId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get kpKey => $composableBuilder(
      column: $table.kpKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get lit => $composableBuilder(
      column: $table.lit, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get litPercent => $composableBuilder(
      column: $table.litPercent, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get questionLevel => $composableBuilder(
      column: $table.questionLevel, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get summaryText => $composableBuilder(
      column: $table.summaryText, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get summaryRawResponse => $composableBuilder(
      column: $table.summaryRawResponse,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get summaryValid => $composableBuilder(
      column: $table.summaryValid, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$ProgressEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $ProgressEntriesTable> {
  $$ProgressEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get studentId => $composableBuilder(
      column: $table.studentId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get courseVersionId => $composableBuilder(
      column: $table.courseVersionId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get kpKey => $composableBuilder(
      column: $table.kpKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get lit => $composableBuilder(
      column: $table.lit, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get litPercent => $composableBuilder(
      column: $table.litPercent, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get questionLevel => $composableBuilder(
      column: $table.questionLevel,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get summaryText => $composableBuilder(
      column: $table.summaryText, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get summaryRawResponse => $composableBuilder(
      column: $table.summaryRawResponse,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get summaryValid => $composableBuilder(
      column: $table.summaryValid,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$ProgressEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProgressEntriesTable> {
  $$ProgressEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get studentId =>
      $composableBuilder(column: $table.studentId, builder: (column) => column);

  GeneratedColumn<int> get courseVersionId => $composableBuilder(
      column: $table.courseVersionId, builder: (column) => column);

  GeneratedColumn<String> get kpKey =>
      $composableBuilder(column: $table.kpKey, builder: (column) => column);

  GeneratedColumn<bool> get lit =>
      $composableBuilder(column: $table.lit, builder: (column) => column);

  GeneratedColumn<int> get litPercent => $composableBuilder(
      column: $table.litPercent, builder: (column) => column);

  GeneratedColumn<String> get questionLevel => $composableBuilder(
      column: $table.questionLevel, builder: (column) => column);

  GeneratedColumn<String> get summaryText => $composableBuilder(
      column: $table.summaryText, builder: (column) => column);

  GeneratedColumn<String> get summaryRawResponse => $composableBuilder(
      column: $table.summaryRawResponse, builder: (column) => column);

  GeneratedColumn<bool> get summaryValid => $composableBuilder(
      column: $table.summaryValid, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ProgressEntriesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ProgressEntriesTable,
    ProgressEntry,
    $$ProgressEntriesTableFilterComposer,
    $$ProgressEntriesTableOrderingComposer,
    $$ProgressEntriesTableAnnotationComposer,
    $$ProgressEntriesTableCreateCompanionBuilder,
    $$ProgressEntriesTableUpdateCompanionBuilder,
    (
      ProgressEntry,
      BaseReferences<_$AppDatabase, $ProgressEntriesTable, ProgressEntry>
    ),
    ProgressEntry,
    PrefetchHooks Function()> {
  $$ProgressEntriesTableTableManager(
      _$AppDatabase db, $ProgressEntriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProgressEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProgressEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProgressEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> studentId = const Value.absent(),
            Value<int> courseVersionId = const Value.absent(),
            Value<String> kpKey = const Value.absent(),
            Value<bool> lit = const Value.absent(),
            Value<int> litPercent = const Value.absent(),
            Value<String?> questionLevel = const Value.absent(),
            Value<String?> summaryText = const Value.absent(),
            Value<String?> summaryRawResponse = const Value.absent(),
            Value<bool?> summaryValid = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              ProgressEntriesCompanion(
            id: id,
            studentId: studentId,
            courseVersionId: courseVersionId,
            kpKey: kpKey,
            lit: lit,
            litPercent: litPercent,
            questionLevel: questionLevel,
            summaryText: summaryText,
            summaryRawResponse: summaryRawResponse,
            summaryValid: summaryValid,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int studentId,
            required int courseVersionId,
            required String kpKey,
            Value<bool> lit = const Value.absent(),
            Value<int> litPercent = const Value.absent(),
            Value<String?> questionLevel = const Value.absent(),
            Value<String?> summaryText = const Value.absent(),
            Value<String?> summaryRawResponse = const Value.absent(),
            Value<bool?> summaryValid = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              ProgressEntriesCompanion.insert(
            id: id,
            studentId: studentId,
            courseVersionId: courseVersionId,
            kpKey: kpKey,
            lit: lit,
            litPercent: litPercent,
            questionLevel: questionLevel,
            summaryText: summaryText,
            summaryRawResponse: summaryRawResponse,
            summaryValid: summaryValid,
            updatedAt: updatedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ProgressEntriesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ProgressEntriesTable,
    ProgressEntry,
    $$ProgressEntriesTableFilterComposer,
    $$ProgressEntriesTableOrderingComposer,
    $$ProgressEntriesTableAnnotationComposer,
    $$ProgressEntriesTableCreateCompanionBuilder,
    $$ProgressEntriesTableUpdateCompanionBuilder,
    (
      ProgressEntry,
      BaseReferences<_$AppDatabase, $ProgressEntriesTable, ProgressEntry>
    ),
    ProgressEntry,
    PrefetchHooks Function()>;
typedef $$ChatSessionsTableCreateCompanionBuilder = ChatSessionsCompanion
    Function({
  Value<int> id,
  required int studentId,
  required int courseVersionId,
  required String kpKey,
  Value<String?> title,
  Value<DateTime> startedAt,
  Value<DateTime?> endedAt,
  Value<String> status,
  Value<String?> summaryText,
  Value<bool?> summaryLit,
  Value<int?> summaryLitPercent,
  Value<String?> summaryRawResponse,
  Value<bool?> summaryValid,
  Value<int?> summarizeCallId,
  Value<String?> controlStateJson,
  Value<DateTime?> controlStateUpdatedAt,
  Value<String?> evidenceStateJson,
  Value<DateTime?> evidenceStateUpdatedAt,
  Value<String?> syncId,
  Value<DateTime?> syncUpdatedAt,
  Value<DateTime?> syncUploadedAt,
});
typedef $$ChatSessionsTableUpdateCompanionBuilder = ChatSessionsCompanion
    Function({
  Value<int> id,
  Value<int> studentId,
  Value<int> courseVersionId,
  Value<String> kpKey,
  Value<String?> title,
  Value<DateTime> startedAt,
  Value<DateTime?> endedAt,
  Value<String> status,
  Value<String?> summaryText,
  Value<bool?> summaryLit,
  Value<int?> summaryLitPercent,
  Value<String?> summaryRawResponse,
  Value<bool?> summaryValid,
  Value<int?> summarizeCallId,
  Value<String?> controlStateJson,
  Value<DateTime?> controlStateUpdatedAt,
  Value<String?> evidenceStateJson,
  Value<DateTime?> evidenceStateUpdatedAt,
  Value<String?> syncId,
  Value<DateTime?> syncUpdatedAt,
  Value<DateTime?> syncUploadedAt,
});

class $$ChatSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $ChatSessionsTable> {
  $$ChatSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get studentId => $composableBuilder(
      column: $table.studentId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get courseVersionId => $composableBuilder(
      column: $table.courseVersionId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get kpKey => $composableBuilder(
      column: $table.kpKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
      column: $table.startedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get endedAt => $composableBuilder(
      column: $table.endedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get summaryText => $composableBuilder(
      column: $table.summaryText, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get summaryLit => $composableBuilder(
      column: $table.summaryLit, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get summaryLitPercent => $composableBuilder(
      column: $table.summaryLitPercent,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get summaryRawResponse => $composableBuilder(
      column: $table.summaryRawResponse,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get summaryValid => $composableBuilder(
      column: $table.summaryValid, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get summarizeCallId => $composableBuilder(
      column: $table.summarizeCallId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get controlStateJson => $composableBuilder(
      column: $table.controlStateJson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get controlStateUpdatedAt => $composableBuilder(
      column: $table.controlStateUpdatedAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get evidenceStateJson => $composableBuilder(
      column: $table.evidenceStateJson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get evidenceStateUpdatedAt => $composableBuilder(
      column: $table.evidenceStateUpdatedAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get syncUpdatedAt => $composableBuilder(
      column: $table.syncUpdatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get syncUploadedAt => $composableBuilder(
      column: $table.syncUploadedAt,
      builder: (column) => ColumnFilters(column));
}

class $$ChatSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $ChatSessionsTable> {
  $$ChatSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get studentId => $composableBuilder(
      column: $table.studentId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get courseVersionId => $composableBuilder(
      column: $table.courseVersionId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get kpKey => $composableBuilder(
      column: $table.kpKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
      column: $table.startedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get endedAt => $composableBuilder(
      column: $table.endedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get summaryText => $composableBuilder(
      column: $table.summaryText, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get summaryLit => $composableBuilder(
      column: $table.summaryLit, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get summaryLitPercent => $composableBuilder(
      column: $table.summaryLitPercent,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get summaryRawResponse => $composableBuilder(
      column: $table.summaryRawResponse,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get summaryValid => $composableBuilder(
      column: $table.summaryValid,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get summarizeCallId => $composableBuilder(
      column: $table.summarizeCallId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get controlStateJson => $composableBuilder(
      column: $table.controlStateJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get controlStateUpdatedAt => $composableBuilder(
      column: $table.controlStateUpdatedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get evidenceStateJson => $composableBuilder(
      column: $table.evidenceStateJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get evidenceStateUpdatedAt => $composableBuilder(
      column: $table.evidenceStateUpdatedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get syncUpdatedAt => $composableBuilder(
      column: $table.syncUpdatedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get syncUploadedAt => $composableBuilder(
      column: $table.syncUploadedAt,
      builder: (column) => ColumnOrderings(column));
}

class $$ChatSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChatSessionsTable> {
  $$ChatSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get studentId =>
      $composableBuilder(column: $table.studentId, builder: (column) => column);

  GeneratedColumn<int> get courseVersionId => $composableBuilder(
      column: $table.courseVersionId, builder: (column) => column);

  GeneratedColumn<String> get kpKey =>
      $composableBuilder(column: $table.kpKey, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get summaryText => $composableBuilder(
      column: $table.summaryText, builder: (column) => column);

  GeneratedColumn<bool> get summaryLit => $composableBuilder(
      column: $table.summaryLit, builder: (column) => column);

  GeneratedColumn<int> get summaryLitPercent => $composableBuilder(
      column: $table.summaryLitPercent, builder: (column) => column);

  GeneratedColumn<String> get summaryRawResponse => $composableBuilder(
      column: $table.summaryRawResponse, builder: (column) => column);

  GeneratedColumn<bool> get summaryValid => $composableBuilder(
      column: $table.summaryValid, builder: (column) => column);

  GeneratedColumn<int> get summarizeCallId => $composableBuilder(
      column: $table.summarizeCallId, builder: (column) => column);

  GeneratedColumn<String> get controlStateJson => $composableBuilder(
      column: $table.controlStateJson, builder: (column) => column);

  GeneratedColumn<DateTime> get controlStateUpdatedAt => $composableBuilder(
      column: $table.controlStateUpdatedAt, builder: (column) => column);

  GeneratedColumn<String> get evidenceStateJson => $composableBuilder(
      column: $table.evidenceStateJson, builder: (column) => column);

  GeneratedColumn<DateTime> get evidenceStateUpdatedAt => $composableBuilder(
      column: $table.evidenceStateUpdatedAt, builder: (column) => column);

  GeneratedColumn<String> get syncId =>
      $composableBuilder(column: $table.syncId, builder: (column) => column);

  GeneratedColumn<DateTime> get syncUpdatedAt => $composableBuilder(
      column: $table.syncUpdatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get syncUploadedAt => $composableBuilder(
      column: $table.syncUploadedAt, builder: (column) => column);
}

class $$ChatSessionsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ChatSessionsTable,
    ChatSession,
    $$ChatSessionsTableFilterComposer,
    $$ChatSessionsTableOrderingComposer,
    $$ChatSessionsTableAnnotationComposer,
    $$ChatSessionsTableCreateCompanionBuilder,
    $$ChatSessionsTableUpdateCompanionBuilder,
    (
      ChatSession,
      BaseReferences<_$AppDatabase, $ChatSessionsTable, ChatSession>
    ),
    ChatSession,
    PrefetchHooks Function()> {
  $$ChatSessionsTableTableManager(_$AppDatabase db, $ChatSessionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> studentId = const Value.absent(),
            Value<int> courseVersionId = const Value.absent(),
            Value<String> kpKey = const Value.absent(),
            Value<String?> title = const Value.absent(),
            Value<DateTime> startedAt = const Value.absent(),
            Value<DateTime?> endedAt = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String?> summaryText = const Value.absent(),
            Value<bool?> summaryLit = const Value.absent(),
            Value<int?> summaryLitPercent = const Value.absent(),
            Value<String?> summaryRawResponse = const Value.absent(),
            Value<bool?> summaryValid = const Value.absent(),
            Value<int?> summarizeCallId = const Value.absent(),
            Value<String?> controlStateJson = const Value.absent(),
            Value<DateTime?> controlStateUpdatedAt = const Value.absent(),
            Value<String?> evidenceStateJson = const Value.absent(),
            Value<DateTime?> evidenceStateUpdatedAt = const Value.absent(),
            Value<String?> syncId = const Value.absent(),
            Value<DateTime?> syncUpdatedAt = const Value.absent(),
            Value<DateTime?> syncUploadedAt = const Value.absent(),
          }) =>
              ChatSessionsCompanion(
            id: id,
            studentId: studentId,
            courseVersionId: courseVersionId,
            kpKey: kpKey,
            title: title,
            startedAt: startedAt,
            endedAt: endedAt,
            status: status,
            summaryText: summaryText,
            summaryLit: summaryLit,
            summaryLitPercent: summaryLitPercent,
            summaryRawResponse: summaryRawResponse,
            summaryValid: summaryValid,
            summarizeCallId: summarizeCallId,
            controlStateJson: controlStateJson,
            controlStateUpdatedAt: controlStateUpdatedAt,
            evidenceStateJson: evidenceStateJson,
            evidenceStateUpdatedAt: evidenceStateUpdatedAt,
            syncId: syncId,
            syncUpdatedAt: syncUpdatedAt,
            syncUploadedAt: syncUploadedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int studentId,
            required int courseVersionId,
            required String kpKey,
            Value<String?> title = const Value.absent(),
            Value<DateTime> startedAt = const Value.absent(),
            Value<DateTime?> endedAt = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String?> summaryText = const Value.absent(),
            Value<bool?> summaryLit = const Value.absent(),
            Value<int?> summaryLitPercent = const Value.absent(),
            Value<String?> summaryRawResponse = const Value.absent(),
            Value<bool?> summaryValid = const Value.absent(),
            Value<int?> summarizeCallId = const Value.absent(),
            Value<String?> controlStateJson = const Value.absent(),
            Value<DateTime?> controlStateUpdatedAt = const Value.absent(),
            Value<String?> evidenceStateJson = const Value.absent(),
            Value<DateTime?> evidenceStateUpdatedAt = const Value.absent(),
            Value<String?> syncId = const Value.absent(),
            Value<DateTime?> syncUpdatedAt = const Value.absent(),
            Value<DateTime?> syncUploadedAt = const Value.absent(),
          }) =>
              ChatSessionsCompanion.insert(
            id: id,
            studentId: studentId,
            courseVersionId: courseVersionId,
            kpKey: kpKey,
            title: title,
            startedAt: startedAt,
            endedAt: endedAt,
            status: status,
            summaryText: summaryText,
            summaryLit: summaryLit,
            summaryLitPercent: summaryLitPercent,
            summaryRawResponse: summaryRawResponse,
            summaryValid: summaryValid,
            summarizeCallId: summarizeCallId,
            controlStateJson: controlStateJson,
            controlStateUpdatedAt: controlStateUpdatedAt,
            evidenceStateJson: evidenceStateJson,
            evidenceStateUpdatedAt: evidenceStateUpdatedAt,
            syncId: syncId,
            syncUpdatedAt: syncUpdatedAt,
            syncUploadedAt: syncUploadedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ChatSessionsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ChatSessionsTable,
    ChatSession,
    $$ChatSessionsTableFilterComposer,
    $$ChatSessionsTableOrderingComposer,
    $$ChatSessionsTableAnnotationComposer,
    $$ChatSessionsTableCreateCompanionBuilder,
    $$ChatSessionsTableUpdateCompanionBuilder,
    (
      ChatSession,
      BaseReferences<_$AppDatabase, $ChatSessionsTable, ChatSession>
    ),
    ChatSession,
    PrefetchHooks Function()>;
typedef $$ChatMessagesTableCreateCompanionBuilder = ChatMessagesCompanion
    Function({
  Value<int> id,
  required int sessionId,
  required String role,
  required String content,
  Value<String?> rawContent,
  Value<String?> parsedJson,
  Value<String?> action,
  Value<DateTime> createdAt,
});
typedef $$ChatMessagesTableUpdateCompanionBuilder = ChatMessagesCompanion
    Function({
  Value<int> id,
  Value<int> sessionId,
  Value<String> role,
  Value<String> content,
  Value<String?> rawContent,
  Value<String?> parsedJson,
  Value<String?> action,
  Value<DateTime> createdAt,
});

class $$ChatMessagesTableFilterComposer
    extends Composer<_$AppDatabase, $ChatMessagesTable> {
  $$ChatMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sessionId => $composableBuilder(
      column: $table.sessionId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get rawContent => $composableBuilder(
      column: $table.rawContent, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get parsedJson => $composableBuilder(
      column: $table.parsedJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get action => $composableBuilder(
      column: $table.action, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$ChatMessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $ChatMessagesTable> {
  $$ChatMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sessionId => $composableBuilder(
      column: $table.sessionId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get rawContent => $composableBuilder(
      column: $table.rawContent, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get parsedJson => $composableBuilder(
      column: $table.parsedJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get action => $composableBuilder(
      column: $table.action, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$ChatMessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChatMessagesTable> {
  $$ChatMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get rawContent => $composableBuilder(
      column: $table.rawContent, builder: (column) => column);

  GeneratedColumn<String> get parsedJson => $composableBuilder(
      column: $table.parsedJson, builder: (column) => column);

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ChatMessagesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ChatMessagesTable,
    ChatMessage,
    $$ChatMessagesTableFilterComposer,
    $$ChatMessagesTableOrderingComposer,
    $$ChatMessagesTableAnnotationComposer,
    $$ChatMessagesTableCreateCompanionBuilder,
    $$ChatMessagesTableUpdateCompanionBuilder,
    (
      ChatMessage,
      BaseReferences<_$AppDatabase, $ChatMessagesTable, ChatMessage>
    ),
    ChatMessage,
    PrefetchHooks Function()> {
  $$ChatMessagesTableTableManager(_$AppDatabase db, $ChatMessagesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> sessionId = const Value.absent(),
            Value<String> role = const Value.absent(),
            Value<String> content = const Value.absent(),
            Value<String?> rawContent = const Value.absent(),
            Value<String?> parsedJson = const Value.absent(),
            Value<String?> action = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
          }) =>
              ChatMessagesCompanion(
            id: id,
            sessionId: sessionId,
            role: role,
            content: content,
            rawContent: rawContent,
            parsedJson: parsedJson,
            action: action,
            createdAt: createdAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int sessionId,
            required String role,
            required String content,
            Value<String?> rawContent = const Value.absent(),
            Value<String?> parsedJson = const Value.absent(),
            Value<String?> action = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
          }) =>
              ChatMessagesCompanion.insert(
            id: id,
            sessionId: sessionId,
            role: role,
            content: content,
            rawContent: rawContent,
            parsedJson: parsedJson,
            action: action,
            createdAt: createdAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ChatMessagesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ChatMessagesTable,
    ChatMessage,
    $$ChatMessagesTableFilterComposer,
    $$ChatMessagesTableOrderingComposer,
    $$ChatMessagesTableAnnotationComposer,
    $$ChatMessagesTableCreateCompanionBuilder,
    $$ChatMessagesTableUpdateCompanionBuilder,
    (
      ChatMessage,
      BaseReferences<_$AppDatabase, $ChatMessagesTable, ChatMessage>
    ),
    ChatMessage,
    PrefetchHooks Function()>;
typedef $$LlmCallsTableCreateCompanionBuilder = LlmCallsCompanion Function({
  Value<int> id,
  required String callHash,
  required String promptName,
  required String renderedPrompt,
  required String model,
  required String baseUrl,
  Value<String?> responseText,
  Value<String?> responseJson,
  Value<bool?> parseValid,
  Value<String?> parseError,
  Value<int?> latencyMs,
  Value<int?> teacherId,
  Value<int?> studentId,
  Value<int?> courseVersionId,
  Value<int?> sessionId,
  Value<String?> kpKey,
  Value<String?> action,
  Value<DateTime> createdAt,
  required String mode,
});
typedef $$LlmCallsTableUpdateCompanionBuilder = LlmCallsCompanion Function({
  Value<int> id,
  Value<String> callHash,
  Value<String> promptName,
  Value<String> renderedPrompt,
  Value<String> model,
  Value<String> baseUrl,
  Value<String?> responseText,
  Value<String?> responseJson,
  Value<bool?> parseValid,
  Value<String?> parseError,
  Value<int?> latencyMs,
  Value<int?> teacherId,
  Value<int?> studentId,
  Value<int?> courseVersionId,
  Value<int?> sessionId,
  Value<String?> kpKey,
  Value<String?> action,
  Value<DateTime> createdAt,
  Value<String> mode,
});

class $$LlmCallsTableFilterComposer
    extends Composer<_$AppDatabase, $LlmCallsTable> {
  $$LlmCallsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get callHash => $composableBuilder(
      column: $table.callHash, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get promptName => $composableBuilder(
      column: $table.promptName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get renderedPrompt => $composableBuilder(
      column: $table.renderedPrompt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get model => $composableBuilder(
      column: $table.model, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get baseUrl => $composableBuilder(
      column: $table.baseUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get responseText => $composableBuilder(
      column: $table.responseText, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get responseJson => $composableBuilder(
      column: $table.responseJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get parseValid => $composableBuilder(
      column: $table.parseValid, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get parseError => $composableBuilder(
      column: $table.parseError, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get latencyMs => $composableBuilder(
      column: $table.latencyMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get teacherId => $composableBuilder(
      column: $table.teacherId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get studentId => $composableBuilder(
      column: $table.studentId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get courseVersionId => $composableBuilder(
      column: $table.courseVersionId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sessionId => $composableBuilder(
      column: $table.sessionId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get kpKey => $composableBuilder(
      column: $table.kpKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get action => $composableBuilder(
      column: $table.action, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mode => $composableBuilder(
      column: $table.mode, builder: (column) => ColumnFilters(column));
}

class $$LlmCallsTableOrderingComposer
    extends Composer<_$AppDatabase, $LlmCallsTable> {
  $$LlmCallsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get callHash => $composableBuilder(
      column: $table.callHash, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get promptName => $composableBuilder(
      column: $table.promptName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get renderedPrompt => $composableBuilder(
      column: $table.renderedPrompt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get model => $composableBuilder(
      column: $table.model, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get baseUrl => $composableBuilder(
      column: $table.baseUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get responseText => $composableBuilder(
      column: $table.responseText,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get responseJson => $composableBuilder(
      column: $table.responseJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get parseValid => $composableBuilder(
      column: $table.parseValid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get parseError => $composableBuilder(
      column: $table.parseError, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get latencyMs => $composableBuilder(
      column: $table.latencyMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get teacherId => $composableBuilder(
      column: $table.teacherId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get studentId => $composableBuilder(
      column: $table.studentId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get courseVersionId => $composableBuilder(
      column: $table.courseVersionId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sessionId => $composableBuilder(
      column: $table.sessionId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get kpKey => $composableBuilder(
      column: $table.kpKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get action => $composableBuilder(
      column: $table.action, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mode => $composableBuilder(
      column: $table.mode, builder: (column) => ColumnOrderings(column));
}

class $$LlmCallsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LlmCallsTable> {
  $$LlmCallsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get callHash =>
      $composableBuilder(column: $table.callHash, builder: (column) => column);

  GeneratedColumn<String> get promptName => $composableBuilder(
      column: $table.promptName, builder: (column) => column);

  GeneratedColumn<String> get renderedPrompt => $composableBuilder(
      column: $table.renderedPrompt, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<String> get baseUrl =>
      $composableBuilder(column: $table.baseUrl, builder: (column) => column);

  GeneratedColumn<String> get responseText => $composableBuilder(
      column: $table.responseText, builder: (column) => column);

  GeneratedColumn<String> get responseJson => $composableBuilder(
      column: $table.responseJson, builder: (column) => column);

  GeneratedColumn<bool> get parseValid => $composableBuilder(
      column: $table.parseValid, builder: (column) => column);

  GeneratedColumn<String> get parseError => $composableBuilder(
      column: $table.parseError, builder: (column) => column);

  GeneratedColumn<int> get latencyMs =>
      $composableBuilder(column: $table.latencyMs, builder: (column) => column);

  GeneratedColumn<int> get teacherId =>
      $composableBuilder(column: $table.teacherId, builder: (column) => column);

  GeneratedColumn<int> get studentId =>
      $composableBuilder(column: $table.studentId, builder: (column) => column);

  GeneratedColumn<int> get courseVersionId => $composableBuilder(
      column: $table.courseVersionId, builder: (column) => column);

  GeneratedColumn<int> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get kpKey =>
      $composableBuilder(column: $table.kpKey, builder: (column) => column);

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);
}

class $$LlmCallsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $LlmCallsTable,
    LlmCall,
    $$LlmCallsTableFilterComposer,
    $$LlmCallsTableOrderingComposer,
    $$LlmCallsTableAnnotationComposer,
    $$LlmCallsTableCreateCompanionBuilder,
    $$LlmCallsTableUpdateCompanionBuilder,
    (LlmCall, BaseReferences<_$AppDatabase, $LlmCallsTable, LlmCall>),
    LlmCall,
    PrefetchHooks Function()> {
  $$LlmCallsTableTableManager(_$AppDatabase db, $LlmCallsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LlmCallsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LlmCallsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LlmCallsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> callHash = const Value.absent(),
            Value<String> promptName = const Value.absent(),
            Value<String> renderedPrompt = const Value.absent(),
            Value<String> model = const Value.absent(),
            Value<String> baseUrl = const Value.absent(),
            Value<String?> responseText = const Value.absent(),
            Value<String?> responseJson = const Value.absent(),
            Value<bool?> parseValid = const Value.absent(),
            Value<String?> parseError = const Value.absent(),
            Value<int?> latencyMs = const Value.absent(),
            Value<int?> teacherId = const Value.absent(),
            Value<int?> studentId = const Value.absent(),
            Value<int?> courseVersionId = const Value.absent(),
            Value<int?> sessionId = const Value.absent(),
            Value<String?> kpKey = const Value.absent(),
            Value<String?> action = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<String> mode = const Value.absent(),
          }) =>
              LlmCallsCompanion(
            id: id,
            callHash: callHash,
            promptName: promptName,
            renderedPrompt: renderedPrompt,
            model: model,
            baseUrl: baseUrl,
            responseText: responseText,
            responseJson: responseJson,
            parseValid: parseValid,
            parseError: parseError,
            latencyMs: latencyMs,
            teacherId: teacherId,
            studentId: studentId,
            courseVersionId: courseVersionId,
            sessionId: sessionId,
            kpKey: kpKey,
            action: action,
            createdAt: createdAt,
            mode: mode,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String callHash,
            required String promptName,
            required String renderedPrompt,
            required String model,
            required String baseUrl,
            Value<String?> responseText = const Value.absent(),
            Value<String?> responseJson = const Value.absent(),
            Value<bool?> parseValid = const Value.absent(),
            Value<String?> parseError = const Value.absent(),
            Value<int?> latencyMs = const Value.absent(),
            Value<int?> teacherId = const Value.absent(),
            Value<int?> studentId = const Value.absent(),
            Value<int?> courseVersionId = const Value.absent(),
            Value<int?> sessionId = const Value.absent(),
            Value<String?> kpKey = const Value.absent(),
            Value<String?> action = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            required String mode,
          }) =>
              LlmCallsCompanion.insert(
            id: id,
            callHash: callHash,
            promptName: promptName,
            renderedPrompt: renderedPrompt,
            model: model,
            baseUrl: baseUrl,
            responseText: responseText,
            responseJson: responseJson,
            parseValid: parseValid,
            parseError: parseError,
            latencyMs: latencyMs,
            teacherId: teacherId,
            studentId: studentId,
            courseVersionId: courseVersionId,
            sessionId: sessionId,
            kpKey: kpKey,
            action: action,
            createdAt: createdAt,
            mode: mode,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LlmCallsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $LlmCallsTable,
    LlmCall,
    $$LlmCallsTableFilterComposer,
    $$LlmCallsTableOrderingComposer,
    $$LlmCallsTableAnnotationComposer,
    $$LlmCallsTableCreateCompanionBuilder,
    $$LlmCallsTableUpdateCompanionBuilder,
    (LlmCall, BaseReferences<_$AppDatabase, $LlmCallsTable, LlmCall>),
    LlmCall,
    PrefetchHooks Function()>;
typedef $$AppSettingsTableCreateCompanionBuilder = AppSettingsCompanion
    Function({
  Value<int> id,
  required String baseUrl,
  Value<String?> providerId,
  required String model,
  Value<String> reasoningEffort,
  Value<String?> ttsModel,
  Value<String?> sttModel,
  required int timeoutSeconds,
  required int maxTokens,
  Value<int> ttsInitialDelayMs,
  Value<int> ttsTextLeadMs,
  Value<String?> ttsAudioPath,
  Value<bool> sttAutoSend,
  Value<bool> enterToSend,
  Value<bool> studyModeEnabled,
  Value<String?> logDirectory,
  Value<String?> llmLogPath,
  Value<String?> ttsLogPath,
  required String llmMode,
  Value<String?> locale,
  Value<DateTime> updatedAt,
});
typedef $$AppSettingsTableUpdateCompanionBuilder = AppSettingsCompanion
    Function({
  Value<int> id,
  Value<String> baseUrl,
  Value<String?> providerId,
  Value<String> model,
  Value<String> reasoningEffort,
  Value<String?> ttsModel,
  Value<String?> sttModel,
  Value<int> timeoutSeconds,
  Value<int> maxTokens,
  Value<int> ttsInitialDelayMs,
  Value<int> ttsTextLeadMs,
  Value<String?> ttsAudioPath,
  Value<bool> sttAutoSend,
  Value<bool> enterToSend,
  Value<bool> studyModeEnabled,
  Value<String?> logDirectory,
  Value<String?> llmLogPath,
  Value<String?> ttsLogPath,
  Value<String> llmMode,
  Value<String?> locale,
  Value<DateTime> updatedAt,
});

class $$AppSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get baseUrl => $composableBuilder(
      column: $table.baseUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get providerId => $composableBuilder(
      column: $table.providerId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get model => $composableBuilder(
      column: $table.model, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get reasoningEffort => $composableBuilder(
      column: $table.reasoningEffort,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get ttsModel => $composableBuilder(
      column: $table.ttsModel, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sttModel => $composableBuilder(
      column: $table.sttModel, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get timeoutSeconds => $composableBuilder(
      column: $table.timeoutSeconds,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get maxTokens => $composableBuilder(
      column: $table.maxTokens, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get ttsInitialDelayMs => $composableBuilder(
      column: $table.ttsInitialDelayMs,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get ttsTextLeadMs => $composableBuilder(
      column: $table.ttsTextLeadMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get ttsAudioPath => $composableBuilder(
      column: $table.ttsAudioPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get sttAutoSend => $composableBuilder(
      column: $table.sttAutoSend, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get enterToSend => $composableBuilder(
      column: $table.enterToSend, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get studyModeEnabled => $composableBuilder(
      column: $table.studyModeEnabled,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get logDirectory => $composableBuilder(
      column: $table.logDirectory, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get llmLogPath => $composableBuilder(
      column: $table.llmLogPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get ttsLogPath => $composableBuilder(
      column: $table.ttsLogPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get llmMode => $composableBuilder(
      column: $table.llmMode, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get locale => $composableBuilder(
      column: $table.locale, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get baseUrl => $composableBuilder(
      column: $table.baseUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get providerId => $composableBuilder(
      column: $table.providerId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get model => $composableBuilder(
      column: $table.model, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get reasoningEffort => $composableBuilder(
      column: $table.reasoningEffort,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get ttsModel => $composableBuilder(
      column: $table.ttsModel, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sttModel => $composableBuilder(
      column: $table.sttModel, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get timeoutSeconds => $composableBuilder(
      column: $table.timeoutSeconds,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get maxTokens => $composableBuilder(
      column: $table.maxTokens, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get ttsInitialDelayMs => $composableBuilder(
      column: $table.ttsInitialDelayMs,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get ttsTextLeadMs => $composableBuilder(
      column: $table.ttsTextLeadMs,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get ttsAudioPath => $composableBuilder(
      column: $table.ttsAudioPath,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get sttAutoSend => $composableBuilder(
      column: $table.sttAutoSend, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get enterToSend => $composableBuilder(
      column: $table.enterToSend, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get studyModeEnabled => $composableBuilder(
      column: $table.studyModeEnabled,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get logDirectory => $composableBuilder(
      column: $table.logDirectory,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get llmLogPath => $composableBuilder(
      column: $table.llmLogPath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get ttsLogPath => $composableBuilder(
      column: $table.ttsLogPath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get llmMode => $composableBuilder(
      column: $table.llmMode, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get locale => $composableBuilder(
      column: $table.locale, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get baseUrl =>
      $composableBuilder(column: $table.baseUrl, builder: (column) => column);

  GeneratedColumn<String> get providerId => $composableBuilder(
      column: $table.providerId, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<String> get reasoningEffort => $composableBuilder(
      column: $table.reasoningEffort, builder: (column) => column);

  GeneratedColumn<String> get ttsModel =>
      $composableBuilder(column: $table.ttsModel, builder: (column) => column);

  GeneratedColumn<String> get sttModel =>
      $composableBuilder(column: $table.sttModel, builder: (column) => column);

  GeneratedColumn<int> get timeoutSeconds => $composableBuilder(
      column: $table.timeoutSeconds, builder: (column) => column);

  GeneratedColumn<int> get maxTokens =>
      $composableBuilder(column: $table.maxTokens, builder: (column) => column);

  GeneratedColumn<int> get ttsInitialDelayMs => $composableBuilder(
      column: $table.ttsInitialDelayMs, builder: (column) => column);

  GeneratedColumn<int> get ttsTextLeadMs => $composableBuilder(
      column: $table.ttsTextLeadMs, builder: (column) => column);

  GeneratedColumn<String> get ttsAudioPath => $composableBuilder(
      column: $table.ttsAudioPath, builder: (column) => column);

  GeneratedColumn<bool> get sttAutoSend => $composableBuilder(
      column: $table.sttAutoSend, builder: (column) => column);

  GeneratedColumn<bool> get enterToSend => $composableBuilder(
      column: $table.enterToSend, builder: (column) => column);

  GeneratedColumn<bool> get studyModeEnabled => $composableBuilder(
      column: $table.studyModeEnabled, builder: (column) => column);

  GeneratedColumn<String> get logDirectory => $composableBuilder(
      column: $table.logDirectory, builder: (column) => column);

  GeneratedColumn<String> get llmLogPath => $composableBuilder(
      column: $table.llmLogPath, builder: (column) => column);

  GeneratedColumn<String> get ttsLogPath => $composableBuilder(
      column: $table.ttsLogPath, builder: (column) => column);

  GeneratedColumn<String> get llmMode =>
      $composableBuilder(column: $table.llmMode, builder: (column) => column);

  GeneratedColumn<String> get locale =>
      $composableBuilder(column: $table.locale, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AppSettingsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AppSettingsTable,
    AppSetting,
    $$AppSettingsTableFilterComposer,
    $$AppSettingsTableOrderingComposer,
    $$AppSettingsTableAnnotationComposer,
    $$AppSettingsTableCreateCompanionBuilder,
    $$AppSettingsTableUpdateCompanionBuilder,
    (AppSetting, BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>),
    AppSetting,
    PrefetchHooks Function()> {
  $$AppSettingsTableTableManager(_$AppDatabase db, $AppSettingsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> baseUrl = const Value.absent(),
            Value<String?> providerId = const Value.absent(),
            Value<String> model = const Value.absent(),
            Value<String> reasoningEffort = const Value.absent(),
            Value<String?> ttsModel = const Value.absent(),
            Value<String?> sttModel = const Value.absent(),
            Value<int> timeoutSeconds = const Value.absent(),
            Value<int> maxTokens = const Value.absent(),
            Value<int> ttsInitialDelayMs = const Value.absent(),
            Value<int> ttsTextLeadMs = const Value.absent(),
            Value<String?> ttsAudioPath = const Value.absent(),
            Value<bool> sttAutoSend = const Value.absent(),
            Value<bool> enterToSend = const Value.absent(),
            Value<bool> studyModeEnabled = const Value.absent(),
            Value<String?> logDirectory = const Value.absent(),
            Value<String?> llmLogPath = const Value.absent(),
            Value<String?> ttsLogPath = const Value.absent(),
            Value<String> llmMode = const Value.absent(),
            Value<String?> locale = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              AppSettingsCompanion(
            id: id,
            baseUrl: baseUrl,
            providerId: providerId,
            model: model,
            reasoningEffort: reasoningEffort,
            ttsModel: ttsModel,
            sttModel: sttModel,
            timeoutSeconds: timeoutSeconds,
            maxTokens: maxTokens,
            ttsInitialDelayMs: ttsInitialDelayMs,
            ttsTextLeadMs: ttsTextLeadMs,
            ttsAudioPath: ttsAudioPath,
            sttAutoSend: sttAutoSend,
            enterToSend: enterToSend,
            studyModeEnabled: studyModeEnabled,
            logDirectory: logDirectory,
            llmLogPath: llmLogPath,
            ttsLogPath: ttsLogPath,
            llmMode: llmMode,
            locale: locale,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String baseUrl,
            Value<String?> providerId = const Value.absent(),
            required String model,
            Value<String> reasoningEffort = const Value.absent(),
            Value<String?> ttsModel = const Value.absent(),
            Value<String?> sttModel = const Value.absent(),
            required int timeoutSeconds,
            required int maxTokens,
            Value<int> ttsInitialDelayMs = const Value.absent(),
            Value<int> ttsTextLeadMs = const Value.absent(),
            Value<String?> ttsAudioPath = const Value.absent(),
            Value<bool> sttAutoSend = const Value.absent(),
            Value<bool> enterToSend = const Value.absent(),
            Value<bool> studyModeEnabled = const Value.absent(),
            Value<String?> logDirectory = const Value.absent(),
            Value<String?> llmLogPath = const Value.absent(),
            Value<String?> ttsLogPath = const Value.absent(),
            required String llmMode,
            Value<String?> locale = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              AppSettingsCompanion.insert(
            id: id,
            baseUrl: baseUrl,
            providerId: providerId,
            model: model,
            reasoningEffort: reasoningEffort,
            ttsModel: ttsModel,
            sttModel: sttModel,
            timeoutSeconds: timeoutSeconds,
            maxTokens: maxTokens,
            ttsInitialDelayMs: ttsInitialDelayMs,
            ttsTextLeadMs: ttsTextLeadMs,
            ttsAudioPath: ttsAudioPath,
            sttAutoSend: sttAutoSend,
            enterToSend: enterToSend,
            studyModeEnabled: studyModeEnabled,
            logDirectory: logDirectory,
            llmLogPath: llmLogPath,
            ttsLogPath: ttsLogPath,
            llmMode: llmMode,
            locale: locale,
            updatedAt: updatedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AppSettingsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $AppSettingsTable,
    AppSetting,
    $$AppSettingsTableFilterComposer,
    $$AppSettingsTableOrderingComposer,
    $$AppSettingsTableAnnotationComposer,
    $$AppSettingsTableCreateCompanionBuilder,
    $$AppSettingsTableUpdateCompanionBuilder,
    (AppSetting, BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>),
    AppSetting,
    PrefetchHooks Function()>;
typedef $$ApiConfigsTableCreateCompanionBuilder = ApiConfigsCompanion Function({
  Value<int> id,
  required String baseUrl,
  required String model,
  Value<String> reasoningEffort,
  Value<String?> ttsModel,
  Value<String?> sttModel,
  required String apiKeyHash,
  Value<DateTime> createdAt,
});
typedef $$ApiConfigsTableUpdateCompanionBuilder = ApiConfigsCompanion Function({
  Value<int> id,
  Value<String> baseUrl,
  Value<String> model,
  Value<String> reasoningEffort,
  Value<String?> ttsModel,
  Value<String?> sttModel,
  Value<String> apiKeyHash,
  Value<DateTime> createdAt,
});

class $$ApiConfigsTableFilterComposer
    extends Composer<_$AppDatabase, $ApiConfigsTable> {
  $$ApiConfigsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get baseUrl => $composableBuilder(
      column: $table.baseUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get model => $composableBuilder(
      column: $table.model, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get reasoningEffort => $composableBuilder(
      column: $table.reasoningEffort,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get ttsModel => $composableBuilder(
      column: $table.ttsModel, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sttModel => $composableBuilder(
      column: $table.sttModel, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get apiKeyHash => $composableBuilder(
      column: $table.apiKeyHash, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$ApiConfigsTableOrderingComposer
    extends Composer<_$AppDatabase, $ApiConfigsTable> {
  $$ApiConfigsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get baseUrl => $composableBuilder(
      column: $table.baseUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get model => $composableBuilder(
      column: $table.model, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get reasoningEffort => $composableBuilder(
      column: $table.reasoningEffort,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get ttsModel => $composableBuilder(
      column: $table.ttsModel, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sttModel => $composableBuilder(
      column: $table.sttModel, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get apiKeyHash => $composableBuilder(
      column: $table.apiKeyHash, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$ApiConfigsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ApiConfigsTable> {
  $$ApiConfigsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get baseUrl =>
      $composableBuilder(column: $table.baseUrl, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<String> get reasoningEffort => $composableBuilder(
      column: $table.reasoningEffort, builder: (column) => column);

  GeneratedColumn<String> get ttsModel =>
      $composableBuilder(column: $table.ttsModel, builder: (column) => column);

  GeneratedColumn<String> get sttModel =>
      $composableBuilder(column: $table.sttModel, builder: (column) => column);

  GeneratedColumn<String> get apiKeyHash => $composableBuilder(
      column: $table.apiKeyHash, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ApiConfigsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ApiConfigsTable,
    ApiConfig,
    $$ApiConfigsTableFilterComposer,
    $$ApiConfigsTableOrderingComposer,
    $$ApiConfigsTableAnnotationComposer,
    $$ApiConfigsTableCreateCompanionBuilder,
    $$ApiConfigsTableUpdateCompanionBuilder,
    (ApiConfig, BaseReferences<_$AppDatabase, $ApiConfigsTable, ApiConfig>),
    ApiConfig,
    PrefetchHooks Function()> {
  $$ApiConfigsTableTableManager(_$AppDatabase db, $ApiConfigsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ApiConfigsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ApiConfigsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ApiConfigsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> baseUrl = const Value.absent(),
            Value<String> model = const Value.absent(),
            Value<String> reasoningEffort = const Value.absent(),
            Value<String?> ttsModel = const Value.absent(),
            Value<String?> sttModel = const Value.absent(),
            Value<String> apiKeyHash = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
          }) =>
              ApiConfigsCompanion(
            id: id,
            baseUrl: baseUrl,
            model: model,
            reasoningEffort: reasoningEffort,
            ttsModel: ttsModel,
            sttModel: sttModel,
            apiKeyHash: apiKeyHash,
            createdAt: createdAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String baseUrl,
            required String model,
            Value<String> reasoningEffort = const Value.absent(),
            Value<String?> ttsModel = const Value.absent(),
            Value<String?> sttModel = const Value.absent(),
            required String apiKeyHash,
            Value<DateTime> createdAt = const Value.absent(),
          }) =>
              ApiConfigsCompanion.insert(
            id: id,
            baseUrl: baseUrl,
            model: model,
            reasoningEffort: reasoningEffort,
            ttsModel: ttsModel,
            sttModel: sttModel,
            apiKeyHash: apiKeyHash,
            createdAt: createdAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ApiConfigsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ApiConfigsTable,
    ApiConfig,
    $$ApiConfigsTableFilterComposer,
    $$ApiConfigsTableOrderingComposer,
    $$ApiConfigsTableAnnotationComposer,
    $$ApiConfigsTableCreateCompanionBuilder,
    $$ApiConfigsTableUpdateCompanionBuilder,
    (ApiConfig, BaseReferences<_$AppDatabase, $ApiConfigsTable, ApiConfig>),
    ApiConfig,
    PrefetchHooks Function()>;
typedef $$PromptTemplatesTableCreateCompanionBuilder = PromptTemplatesCompanion
    Function({
  Value<int> id,
  required int teacherId,
  Value<String?> courseKey,
  Value<int?> studentId,
  required String promptName,
  required String content,
  Value<bool> isActive,
  Value<DateTime> createdAt,
});
typedef $$PromptTemplatesTableUpdateCompanionBuilder = PromptTemplatesCompanion
    Function({
  Value<int> id,
  Value<int> teacherId,
  Value<String?> courseKey,
  Value<int?> studentId,
  Value<String> promptName,
  Value<String> content,
  Value<bool> isActive,
  Value<DateTime> createdAt,
});

class $$PromptTemplatesTableFilterComposer
    extends Composer<_$AppDatabase, $PromptTemplatesTable> {
  $$PromptTemplatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get teacherId => $composableBuilder(
      column: $table.teacherId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get courseKey => $composableBuilder(
      column: $table.courseKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get studentId => $composableBuilder(
      column: $table.studentId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get promptName => $composableBuilder(
      column: $table.promptName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$PromptTemplatesTableOrderingComposer
    extends Composer<_$AppDatabase, $PromptTemplatesTable> {
  $$PromptTemplatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get teacherId => $composableBuilder(
      column: $table.teacherId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get courseKey => $composableBuilder(
      column: $table.courseKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get studentId => $composableBuilder(
      column: $table.studentId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get promptName => $composableBuilder(
      column: $table.promptName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$PromptTemplatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PromptTemplatesTable> {
  $$PromptTemplatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get teacherId =>
      $composableBuilder(column: $table.teacherId, builder: (column) => column);

  GeneratedColumn<String> get courseKey =>
      $composableBuilder(column: $table.courseKey, builder: (column) => column);

  GeneratedColumn<int> get studentId =>
      $composableBuilder(column: $table.studentId, builder: (column) => column);

  GeneratedColumn<String> get promptName => $composableBuilder(
      column: $table.promptName, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$PromptTemplatesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PromptTemplatesTable,
    PromptTemplate,
    $$PromptTemplatesTableFilterComposer,
    $$PromptTemplatesTableOrderingComposer,
    $$PromptTemplatesTableAnnotationComposer,
    $$PromptTemplatesTableCreateCompanionBuilder,
    $$PromptTemplatesTableUpdateCompanionBuilder,
    (
      PromptTemplate,
      BaseReferences<_$AppDatabase, $PromptTemplatesTable, PromptTemplate>
    ),
    PromptTemplate,
    PrefetchHooks Function()> {
  $$PromptTemplatesTableTableManager(
      _$AppDatabase db, $PromptTemplatesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PromptTemplatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PromptTemplatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PromptTemplatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> teacherId = const Value.absent(),
            Value<String?> courseKey = const Value.absent(),
            Value<int?> studentId = const Value.absent(),
            Value<String> promptName = const Value.absent(),
            Value<String> content = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
          }) =>
              PromptTemplatesCompanion(
            id: id,
            teacherId: teacherId,
            courseKey: courseKey,
            studentId: studentId,
            promptName: promptName,
            content: content,
            isActive: isActive,
            createdAt: createdAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int teacherId,
            Value<String?> courseKey = const Value.absent(),
            Value<int?> studentId = const Value.absent(),
            required String promptName,
            required String content,
            Value<bool> isActive = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
          }) =>
              PromptTemplatesCompanion.insert(
            id: id,
            teacherId: teacherId,
            courseKey: courseKey,
            studentId: studentId,
            promptName: promptName,
            content: content,
            isActive: isActive,
            createdAt: createdAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PromptTemplatesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PromptTemplatesTable,
    PromptTemplate,
    $$PromptTemplatesTableFilterComposer,
    $$PromptTemplatesTableOrderingComposer,
    $$PromptTemplatesTableAnnotationComposer,
    $$PromptTemplatesTableCreateCompanionBuilder,
    $$PromptTemplatesTableUpdateCompanionBuilder,
    (
      PromptTemplate,
      BaseReferences<_$AppDatabase, $PromptTemplatesTable, PromptTemplate>
    ),
    PromptTemplate,
    PrefetchHooks Function()>;
typedef $$StudentPromptProfilesTableCreateCompanionBuilder
    = StudentPromptProfilesCompanion Function({
  Value<int> id,
  required int teacherId,
  Value<String?> courseKey,
  Value<int?> studentId,
  Value<String?> gradeLevel,
  Value<String?> readingLevel,
  Value<String?> preferredLanguage,
  Value<String?> interests,
  Value<String?> preferredTone,
  Value<String?> preferredPace,
  Value<String?> preferredFormat,
  Value<String?> supportNotes,
  Value<DateTime> createdAt,
  Value<DateTime?> updatedAt,
});
typedef $$StudentPromptProfilesTableUpdateCompanionBuilder
    = StudentPromptProfilesCompanion Function({
  Value<int> id,
  Value<int> teacherId,
  Value<String?> courseKey,
  Value<int?> studentId,
  Value<String?> gradeLevel,
  Value<String?> readingLevel,
  Value<String?> preferredLanguage,
  Value<String?> interests,
  Value<String?> preferredTone,
  Value<String?> preferredPace,
  Value<String?> preferredFormat,
  Value<String?> supportNotes,
  Value<DateTime> createdAt,
  Value<DateTime?> updatedAt,
});

class $$StudentPromptProfilesTableFilterComposer
    extends Composer<_$AppDatabase, $StudentPromptProfilesTable> {
  $$StudentPromptProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get teacherId => $composableBuilder(
      column: $table.teacherId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get courseKey => $composableBuilder(
      column: $table.courseKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get studentId => $composableBuilder(
      column: $table.studentId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get gradeLevel => $composableBuilder(
      column: $table.gradeLevel, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get readingLevel => $composableBuilder(
      column: $table.readingLevel, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get preferredLanguage => $composableBuilder(
      column: $table.preferredLanguage,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get interests => $composableBuilder(
      column: $table.interests, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get preferredTone => $composableBuilder(
      column: $table.preferredTone, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get preferredPace => $composableBuilder(
      column: $table.preferredPace, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get preferredFormat => $composableBuilder(
      column: $table.preferredFormat,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get supportNotes => $composableBuilder(
      column: $table.supportNotes, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$StudentPromptProfilesTableOrderingComposer
    extends Composer<_$AppDatabase, $StudentPromptProfilesTable> {
  $$StudentPromptProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get teacherId => $composableBuilder(
      column: $table.teacherId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get courseKey => $composableBuilder(
      column: $table.courseKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get studentId => $composableBuilder(
      column: $table.studentId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get gradeLevel => $composableBuilder(
      column: $table.gradeLevel, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get readingLevel => $composableBuilder(
      column: $table.readingLevel,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get preferredLanguage => $composableBuilder(
      column: $table.preferredLanguage,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get interests => $composableBuilder(
      column: $table.interests, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get preferredTone => $composableBuilder(
      column: $table.preferredTone,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get preferredPace => $composableBuilder(
      column: $table.preferredPace,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get preferredFormat => $composableBuilder(
      column: $table.preferredFormat,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get supportNotes => $composableBuilder(
      column: $table.supportNotes,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$StudentPromptProfilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $StudentPromptProfilesTable> {
  $$StudentPromptProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get teacherId =>
      $composableBuilder(column: $table.teacherId, builder: (column) => column);

  GeneratedColumn<String> get courseKey =>
      $composableBuilder(column: $table.courseKey, builder: (column) => column);

  GeneratedColumn<int> get studentId =>
      $composableBuilder(column: $table.studentId, builder: (column) => column);

  GeneratedColumn<String> get gradeLevel => $composableBuilder(
      column: $table.gradeLevel, builder: (column) => column);

  GeneratedColumn<String> get readingLevel => $composableBuilder(
      column: $table.readingLevel, builder: (column) => column);

  GeneratedColumn<String> get preferredLanguage => $composableBuilder(
      column: $table.preferredLanguage, builder: (column) => column);

  GeneratedColumn<String> get interests =>
      $composableBuilder(column: $table.interests, builder: (column) => column);

  GeneratedColumn<String> get preferredTone => $composableBuilder(
      column: $table.preferredTone, builder: (column) => column);

  GeneratedColumn<String> get preferredPace => $composableBuilder(
      column: $table.preferredPace, builder: (column) => column);

  GeneratedColumn<String> get preferredFormat => $composableBuilder(
      column: $table.preferredFormat, builder: (column) => column);

  GeneratedColumn<String> get supportNotes => $composableBuilder(
      column: $table.supportNotes, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$StudentPromptProfilesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $StudentPromptProfilesTable,
    StudentPromptProfile,
    $$StudentPromptProfilesTableFilterComposer,
    $$StudentPromptProfilesTableOrderingComposer,
    $$StudentPromptProfilesTableAnnotationComposer,
    $$StudentPromptProfilesTableCreateCompanionBuilder,
    $$StudentPromptProfilesTableUpdateCompanionBuilder,
    (
      StudentPromptProfile,
      BaseReferences<_$AppDatabase, $StudentPromptProfilesTable,
          StudentPromptProfile>
    ),
    StudentPromptProfile,
    PrefetchHooks Function()> {
  $$StudentPromptProfilesTableTableManager(
      _$AppDatabase db, $StudentPromptProfilesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StudentPromptProfilesTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$StudentPromptProfilesTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StudentPromptProfilesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> teacherId = const Value.absent(),
            Value<String?> courseKey = const Value.absent(),
            Value<int?> studentId = const Value.absent(),
            Value<String?> gradeLevel = const Value.absent(),
            Value<String?> readingLevel = const Value.absent(),
            Value<String?> preferredLanguage = const Value.absent(),
            Value<String?> interests = const Value.absent(),
            Value<String?> preferredTone = const Value.absent(),
            Value<String?> preferredPace = const Value.absent(),
            Value<String?> preferredFormat = const Value.absent(),
            Value<String?> supportNotes = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime?> updatedAt = const Value.absent(),
          }) =>
              StudentPromptProfilesCompanion(
            id: id,
            teacherId: teacherId,
            courseKey: courseKey,
            studentId: studentId,
            gradeLevel: gradeLevel,
            readingLevel: readingLevel,
            preferredLanguage: preferredLanguage,
            interests: interests,
            preferredTone: preferredTone,
            preferredPace: preferredPace,
            preferredFormat: preferredFormat,
            supportNotes: supportNotes,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int teacherId,
            Value<String?> courseKey = const Value.absent(),
            Value<int?> studentId = const Value.absent(),
            Value<String?> gradeLevel = const Value.absent(),
            Value<String?> readingLevel = const Value.absent(),
            Value<String?> preferredLanguage = const Value.absent(),
            Value<String?> interests = const Value.absent(),
            Value<String?> preferredTone = const Value.absent(),
            Value<String?> preferredPace = const Value.absent(),
            Value<String?> preferredFormat = const Value.absent(),
            Value<String?> supportNotes = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime?> updatedAt = const Value.absent(),
          }) =>
              StudentPromptProfilesCompanion.insert(
            id: id,
            teacherId: teacherId,
            courseKey: courseKey,
            studentId: studentId,
            gradeLevel: gradeLevel,
            readingLevel: readingLevel,
            preferredLanguage: preferredLanguage,
            interests: interests,
            preferredTone: preferredTone,
            preferredPace: preferredPace,
            preferredFormat: preferredFormat,
            supportNotes: supportNotes,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$StudentPromptProfilesTableProcessedTableManager
    = ProcessedTableManager<
        _$AppDatabase,
        $StudentPromptProfilesTable,
        StudentPromptProfile,
        $$StudentPromptProfilesTableFilterComposer,
        $$StudentPromptProfilesTableOrderingComposer,
        $$StudentPromptProfilesTableAnnotationComposer,
        $$StudentPromptProfilesTableCreateCompanionBuilder,
        $$StudentPromptProfilesTableUpdateCompanionBuilder,
        (
          StudentPromptProfile,
          BaseReferences<_$AppDatabase, $StudentPromptProfilesTable,
              StudentPromptProfile>
        ),
        StudentPromptProfile,
        PrefetchHooks Function()>;
typedef $$CourseRemoteLinksTableCreateCompanionBuilder
    = CourseRemoteLinksCompanion Function({
  Value<int> id,
  required int courseVersionId,
  required int remoteCourseId,
  Value<DateTime> createdAt,
});
typedef $$CourseRemoteLinksTableUpdateCompanionBuilder
    = CourseRemoteLinksCompanion Function({
  Value<int> id,
  Value<int> courseVersionId,
  Value<int> remoteCourseId,
  Value<DateTime> createdAt,
});

class $$CourseRemoteLinksTableFilterComposer
    extends Composer<_$AppDatabase, $CourseRemoteLinksTable> {
  $$CourseRemoteLinksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get courseVersionId => $composableBuilder(
      column: $table.courseVersionId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get remoteCourseId => $composableBuilder(
      column: $table.remoteCourseId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$CourseRemoteLinksTableOrderingComposer
    extends Composer<_$AppDatabase, $CourseRemoteLinksTable> {
  $$CourseRemoteLinksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get courseVersionId => $composableBuilder(
      column: $table.courseVersionId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get remoteCourseId => $composableBuilder(
      column: $table.remoteCourseId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$CourseRemoteLinksTableAnnotationComposer
    extends Composer<_$AppDatabase, $CourseRemoteLinksTable> {
  $$CourseRemoteLinksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get courseVersionId => $composableBuilder(
      column: $table.courseVersionId, builder: (column) => column);

  GeneratedColumn<int> get remoteCourseId => $composableBuilder(
      column: $table.remoteCourseId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$CourseRemoteLinksTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CourseRemoteLinksTable,
    CourseRemoteLink,
    $$CourseRemoteLinksTableFilterComposer,
    $$CourseRemoteLinksTableOrderingComposer,
    $$CourseRemoteLinksTableAnnotationComposer,
    $$CourseRemoteLinksTableCreateCompanionBuilder,
    $$CourseRemoteLinksTableUpdateCompanionBuilder,
    (
      CourseRemoteLink,
      BaseReferences<_$AppDatabase, $CourseRemoteLinksTable, CourseRemoteLink>
    ),
    CourseRemoteLink,
    PrefetchHooks Function()> {
  $$CourseRemoteLinksTableTableManager(
      _$AppDatabase db, $CourseRemoteLinksTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CourseRemoteLinksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CourseRemoteLinksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CourseRemoteLinksTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> courseVersionId = const Value.absent(),
            Value<int> remoteCourseId = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
          }) =>
              CourseRemoteLinksCompanion(
            id: id,
            courseVersionId: courseVersionId,
            remoteCourseId: remoteCourseId,
            createdAt: createdAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int courseVersionId,
            required int remoteCourseId,
            Value<DateTime> createdAt = const Value.absent(),
          }) =>
              CourseRemoteLinksCompanion.insert(
            id: id,
            courseVersionId: courseVersionId,
            remoteCourseId: remoteCourseId,
            createdAt: createdAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CourseRemoteLinksTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CourseRemoteLinksTable,
    CourseRemoteLink,
    $$CourseRemoteLinksTableFilterComposer,
    $$CourseRemoteLinksTableOrderingComposer,
    $$CourseRemoteLinksTableAnnotationComposer,
    $$CourseRemoteLinksTableCreateCompanionBuilder,
    $$CourseRemoteLinksTableUpdateCompanionBuilder,
    (
      CourseRemoteLink,
      BaseReferences<_$AppDatabase, $CourseRemoteLinksTable, CourseRemoteLink>
    ),
    CourseRemoteLink,
    PrefetchHooks Function()>;
typedef $$SyncItemStatesTableCreateCompanionBuilder = SyncItemStatesCompanion
    Function({
  required int remoteUserId,
  required String domain,
  required String scopeKey,
  required String contentHash,
  required DateTime lastChangedAt,
  required DateTime lastSyncedAt,
  Value<int> rowid,
});
typedef $$SyncItemStatesTableUpdateCompanionBuilder = SyncItemStatesCompanion
    Function({
  Value<int> remoteUserId,
  Value<String> domain,
  Value<String> scopeKey,
  Value<String> contentHash,
  Value<DateTime> lastChangedAt,
  Value<DateTime> lastSyncedAt,
  Value<int> rowid,
});

class $$SyncItemStatesTableFilterComposer
    extends Composer<_$AppDatabase, $SyncItemStatesTable> {
  $$SyncItemStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get remoteUserId => $composableBuilder(
      column: $table.remoteUserId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get domain => $composableBuilder(
      column: $table.domain, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get scopeKey => $composableBuilder(
      column: $table.scopeKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get contentHash => $composableBuilder(
      column: $table.contentHash, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastChangedAt => $composableBuilder(
      column: $table.lastChangedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastSyncedAt => $composableBuilder(
      column: $table.lastSyncedAt, builder: (column) => ColumnFilters(column));
}

class $$SyncItemStatesTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncItemStatesTable> {
  $$SyncItemStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get remoteUserId => $composableBuilder(
      column: $table.remoteUserId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get domain => $composableBuilder(
      column: $table.domain, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get scopeKey => $composableBuilder(
      column: $table.scopeKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get contentHash => $composableBuilder(
      column: $table.contentHash, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastChangedAt => $composableBuilder(
      column: $table.lastChangedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastSyncedAt => $composableBuilder(
      column: $table.lastSyncedAt,
      builder: (column) => ColumnOrderings(column));
}

class $$SyncItemStatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncItemStatesTable> {
  $$SyncItemStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get remoteUserId => $composableBuilder(
      column: $table.remoteUserId, builder: (column) => column);

  GeneratedColumn<String> get domain =>
      $composableBuilder(column: $table.domain, builder: (column) => column);

  GeneratedColumn<String> get scopeKey =>
      $composableBuilder(column: $table.scopeKey, builder: (column) => column);

  GeneratedColumn<String> get contentHash => $composableBuilder(
      column: $table.contentHash, builder: (column) => column);

  GeneratedColumn<DateTime> get lastChangedAt => $composableBuilder(
      column: $table.lastChangedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSyncedAt => $composableBuilder(
      column: $table.lastSyncedAt, builder: (column) => column);
}

class $$SyncItemStatesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SyncItemStatesTable,
    SyncItemState,
    $$SyncItemStatesTableFilterComposer,
    $$SyncItemStatesTableOrderingComposer,
    $$SyncItemStatesTableAnnotationComposer,
    $$SyncItemStatesTableCreateCompanionBuilder,
    $$SyncItemStatesTableUpdateCompanionBuilder,
    (
      SyncItemState,
      BaseReferences<_$AppDatabase, $SyncItemStatesTable, SyncItemState>
    ),
    SyncItemState,
    PrefetchHooks Function()> {
  $$SyncItemStatesTableTableManager(
      _$AppDatabase db, $SyncItemStatesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncItemStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncItemStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncItemStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> remoteUserId = const Value.absent(),
            Value<String> domain = const Value.absent(),
            Value<String> scopeKey = const Value.absent(),
            Value<String> contentHash = const Value.absent(),
            Value<DateTime> lastChangedAt = const Value.absent(),
            Value<DateTime> lastSyncedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncItemStatesCompanion(
            remoteUserId: remoteUserId,
            domain: domain,
            scopeKey: scopeKey,
            contentHash: contentHash,
            lastChangedAt: lastChangedAt,
            lastSyncedAt: lastSyncedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required int remoteUserId,
            required String domain,
            required String scopeKey,
            required String contentHash,
            required DateTime lastChangedAt,
            required DateTime lastSyncedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncItemStatesCompanion.insert(
            remoteUserId: remoteUserId,
            domain: domain,
            scopeKey: scopeKey,
            contentHash: contentHash,
            lastChangedAt: lastChangedAt,
            lastSyncedAt: lastSyncedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SyncItemStatesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SyncItemStatesTable,
    SyncItemState,
    $$SyncItemStatesTableFilterComposer,
    $$SyncItemStatesTableOrderingComposer,
    $$SyncItemStatesTableAnnotationComposer,
    $$SyncItemStatesTableCreateCompanionBuilder,
    $$SyncItemStatesTableUpdateCompanionBuilder,
    (
      SyncItemState,
      BaseReferences<_$AppDatabase, $SyncItemStatesTable, SyncItemState>
    ),
    SyncItemState,
    PrefetchHooks Function()>;
typedef $$SyncMetadataEntriesTableCreateCompanionBuilder
    = SyncMetadataEntriesCompanion Function({
  required int remoteUserId,
  required String kind,
  required String domain,
  required String scopeKey,
  required String value,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});
typedef $$SyncMetadataEntriesTableUpdateCompanionBuilder
    = SyncMetadataEntriesCompanion Function({
  Value<int> remoteUserId,
  Value<String> kind,
  Value<String> domain,
  Value<String> scopeKey,
  Value<String> value,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$SyncMetadataEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $SyncMetadataEntriesTable> {
  $$SyncMetadataEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get remoteUserId => $composableBuilder(
      column: $table.remoteUserId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get domain => $composableBuilder(
      column: $table.domain, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get scopeKey => $composableBuilder(
      column: $table.scopeKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$SyncMetadataEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncMetadataEntriesTable> {
  $$SyncMetadataEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get remoteUserId => $composableBuilder(
      column: $table.remoteUserId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get domain => $composableBuilder(
      column: $table.domain, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get scopeKey => $composableBuilder(
      column: $table.scopeKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$SyncMetadataEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncMetadataEntriesTable> {
  $$SyncMetadataEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get remoteUserId => $composableBuilder(
      column: $table.remoteUserId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get domain =>
      $composableBuilder(column: $table.domain, builder: (column) => column);

  GeneratedColumn<String> get scopeKey =>
      $composableBuilder(column: $table.scopeKey, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SyncMetadataEntriesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SyncMetadataEntriesTable,
    SyncMetadataEntry,
    $$SyncMetadataEntriesTableFilterComposer,
    $$SyncMetadataEntriesTableOrderingComposer,
    $$SyncMetadataEntriesTableAnnotationComposer,
    $$SyncMetadataEntriesTableCreateCompanionBuilder,
    $$SyncMetadataEntriesTableUpdateCompanionBuilder,
    (
      SyncMetadataEntry,
      BaseReferences<_$AppDatabase, $SyncMetadataEntriesTable,
          SyncMetadataEntry>
    ),
    SyncMetadataEntry,
    PrefetchHooks Function()> {
  $$SyncMetadataEntriesTableTableManager(
      _$AppDatabase db, $SyncMetadataEntriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncMetadataEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncMetadataEntriesTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncMetadataEntriesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> remoteUserId = const Value.absent(),
            Value<String> kind = const Value.absent(),
            Value<String> domain = const Value.absent(),
            Value<String> scopeKey = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncMetadataEntriesCompanion(
            remoteUserId: remoteUserId,
            kind: kind,
            domain: domain,
            scopeKey: scopeKey,
            value: value,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required int remoteUserId,
            required String kind,
            required String domain,
            required String scopeKey,
            required String value,
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncMetadataEntriesCompanion.insert(
            remoteUserId: remoteUserId,
            kind: kind,
            domain: domain,
            scopeKey: scopeKey,
            value: value,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SyncMetadataEntriesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SyncMetadataEntriesTable,
    SyncMetadataEntry,
    $$SyncMetadataEntriesTableFilterComposer,
    $$SyncMetadataEntriesTableOrderingComposer,
    $$SyncMetadataEntriesTableAnnotationComposer,
    $$SyncMetadataEntriesTableCreateCompanionBuilder,
    $$SyncMetadataEntriesTableUpdateCompanionBuilder,
    (
      SyncMetadataEntry,
      BaseReferences<_$AppDatabase, $SyncMetadataEntriesTable,
          SyncMetadataEntry>
    ),
    SyncMetadataEntry,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db, _db.users);
  $$CourseVersionsTableTableManager get courseVersions =>
      $$CourseVersionsTableTableManager(_db, _db.courseVersions);
  $$CourseNodesTableTableManager get courseNodes =>
      $$CourseNodesTableTableManager(_db, _db.courseNodes);
  $$CourseEdgesTableTableManager get courseEdges =>
      $$CourseEdgesTableTableManager(_db, _db.courseEdges);
  $$StudentCourseAssignmentsTableTableManager get studentCourseAssignments =>
      $$StudentCourseAssignmentsTableTableManager(
          _db, _db.studentCourseAssignments);
  $$ProgressEntriesTableTableManager get progressEntries =>
      $$ProgressEntriesTableTableManager(_db, _db.progressEntries);
  $$ChatSessionsTableTableManager get chatSessions =>
      $$ChatSessionsTableTableManager(_db, _db.chatSessions);
  $$ChatMessagesTableTableManager get chatMessages =>
      $$ChatMessagesTableTableManager(_db, _db.chatMessages);
  $$LlmCallsTableTableManager get llmCalls =>
      $$LlmCallsTableTableManager(_db, _db.llmCalls);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
  $$ApiConfigsTableTableManager get apiConfigs =>
      $$ApiConfigsTableTableManager(_db, _db.apiConfigs);
  $$PromptTemplatesTableTableManager get promptTemplates =>
      $$PromptTemplatesTableTableManager(_db, _db.promptTemplates);
  $$StudentPromptProfilesTableTableManager get studentPromptProfiles =>
      $$StudentPromptProfilesTableTableManager(_db, _db.studentPromptProfiles);
  $$CourseRemoteLinksTableTableManager get courseRemoteLinks =>
      $$CourseRemoteLinksTableTableManager(_db, _db.courseRemoteLinks);
  $$SyncItemStatesTableTableManager get syncItemStates =>
      $$SyncItemStatesTableTableManager(_db, _db.syncItemStates);
  $$SyncMetadataEntriesTableTableManager get syncMetadataEntries =>
      $$SyncMetadataEntriesTableTableManager(_db, _db.syncMetadataEntries);
}
