#!/usr/bin/env python3
"""Migrate legacy summary mastery results to the new lit/count format.

Legacy summary results used `mastery_level: PASS_EASY|PASS_MEDIUM|PASS_HARD`.
The new format uses:
  - lit: boolean
  - easy_passed_count / medium_passed_count / hard_passed_count

This script migrates:
  1. Local SQLite state in the real app documents database.
  2. Server MySQL mirror rows in `progress_sync` using visible summary text.

For each legacy PASS_* result it treats the summary as:
  - lit = true
  - corresponding *_passed_count >= 1
  - lit_percent = 33/66/100
  - question_level = easy/medium/hard

Server-side `progress_sync` does not currently have passed-count columns, so the
server migration updates only the mirrored fields it actually stores.
"""

from __future__ import annotations

import argparse
import ctypes
import json
import os
from pathlib import Path
import re
import shlex
import sqlite3
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass


PASS_PATTERN = re.compile(r"PASS_(EASY|MEDIUM|HARD)")
LEVEL_TO_PERCENT = {"easy": 33, "medium": 66, "hard": 100}
LEVEL_RANK = {"easy": 1, "medium": 2, "hard": 3}


@dataclass(frozen=True)
class LegacySessionSummary:
    session_id: int
    student_id: int
    course_version_id: int
    kp_key: str
    level: str


def _windows_documents_dir() -> Path | None:
    if os.name != "nt":
        return None
    buf = ctypes.c_wchar_p()
    # FOLDERID_Documents = {FDD39AD0-238F-46AF-ADB4-6C85480369C7}
    folder_id = ctypes.c_byte * 16
    documents_guid = folder_id(
        0xD0,
        0x9A,
        0xD3,
        0xFD,
        0x8F,
        0x23,
        0xAF,
        0x46,
        0xAD,
        0xB4,
        0x6C,
        0x85,
        0x48,
        0x03,
        0x69,
        0xC7,
    )
    shell32 = ctypes.windll.shell32
    ole32 = ctypes.windll.ole32
    result = shell32.SHGetKnownFolderPath(
        ctypes.byref(documents_guid),
        0,
        None,
        ctypes.byref(buf),
    )
    if result != 0:
        return None
    try:
        return Path(buf.value)
    finally:
        ole32.CoTaskMemFree(buf)


def default_local_db_path() -> Path:
    candidates = []
    documents_dir = _windows_documents_dir()
    if documents_dir is not None:
        candidates.append(documents_dir / "family_teacher.db")
    appdata = os.environ.get("APPDATA", "").strip()
    if appdata:
        candidates.append(
            Path(appdata) / "com.example" / "family_teacher" / "family_teacher.db"
        )
    candidates.extend(
        [
            Path.home() / "Documents" / "family_teacher.db",
            Path(r"C:\family_teacher\family_teacher.db"),
        ]
    )
    for candidate in candidates:
        if candidate.exists() and candidate.stat().st_size > 0:
            return candidate
    return candidates[0]


def level_from_mastery(value: str | None) -> str | None:
    if not value:
        return None
    match = PASS_PATTERN.search(value.upper())
    if not match:
        return None
    return match.group(1).lower()


def percent_for_level(level: str) -> int:
    return LEVEL_TO_PERCENT[level]


def max_level(levels: list[str]) -> str:
    return max(levels, key=lambda item: LEVEL_RANK[item])


def parse_legacy_level_from_message(
    parsed_json_text: str | None,
    summary_text: str | None,
) -> str | None:
    if parsed_json_text:
        try:
            parsed = json.loads(parsed_json_text)
            level = level_from_mastery(parsed.get("mastery_level"))
            if level is not None:
                return level
        except json.JSONDecodeError:
            pass
    if summary_text:
        return level_from_mastery(summary_text)
    return None


def find_legacy_local_sessions(con: sqlite3.Connection) -> list[LegacySessionSummary]:
    cur = con.cursor()
    rows = cur.execute(
        """
        SELECT
          s.id,
          s.student_id,
          s.course_version_id,
          s.kp_key,
          s.summary_text,
          (
            SELECT parsed_json
            FROM chat_messages m
            WHERE m.session_id = s.id
              AND m.role = 'assistant'
              AND m.action = 'summary'
            ORDER BY m.id DESC
            LIMIT 1
          ) AS latest_summary_parsed_json
        FROM chat_sessions s
        WHERE s.summary_text IS NOT NULL
        """
    ).fetchall()
    found: list[LegacySessionSummary] = []
    for session_id, student_id, course_version_id, kp_key, summary_text, parsed_json_text in rows:
        level = parse_legacy_level_from_message(parsed_json_text, summary_text)
        if level is None:
            continue
        found.append(
            LegacySessionSummary(
                session_id=session_id,
                student_id=student_id,
                course_version_id=course_version_id,
                kp_key=kp_key,
                level=level,
            )
        )
    return found


def migrate_local_sqlite(db_path: Path, dry_run: bool) -> int:
    if not db_path.exists():
        raise FileNotFoundError(f"Local SQLite DB not found: {db_path}")
    con = sqlite3.connect(str(db_path))
    con.row_factory = sqlite3.Row
    try:
        legacy_sessions = find_legacy_local_sessions(con)
        if not legacy_sessions:
            print(f"[local] no legacy summary rows found in {db_path}")
            return 0
        print(f"[local] found {len(legacy_sessions)} legacy summary sessions in {db_path}")
        rows_changed = 0
        grouped_levels: dict[tuple[int, int, str], set[str]] = defaultdict(set)
        for item in legacy_sessions:
            grouped_levels[(item.student_id, item.course_version_id, item.kp_key)].add(
                item.level
            )
            percent = percent_for_level(item.level)
            print(
                f"[local] session {item.session_id} {item.kp_key}: "
                f"summary_lit -> 1, summary_lit_percent -> {percent}"
            )
            if not dry_run:
                con.execute(
                    """
                    UPDATE chat_sessions
                    SET summary_lit = 1,
                        summary_lit_percent = ?
                    WHERE id = ?
                    """,
                    (percent, item.session_id),
                )
            rows_changed += 1

        for key, levels in grouped_levels.items():
            student_id, course_version_id, kp_key = key
            chosen_level = max_level(list(levels))
            percent = percent_for_level(chosen_level)
            row = con.execute(
                """
                SELECT id, lit, lit_percent, question_level,
                       easy_passed_count, medium_passed_count, hard_passed_count
                FROM progress_entries
                WHERE student_id = ? AND course_version_id = ? AND kp_key = ?
                LIMIT 1
                """,
                (student_id, course_version_id, kp_key),
            ).fetchone()
            if row is None:
                print(f"[local] skip missing progress row for {kp_key}")
                continue
            easy_count = max(row["easy_passed_count"], 1 if "easy" in levels else 0)
            medium_count = max(row["medium_passed_count"], 1 if "medium" in levels else 0)
            hard_count = max(row["hard_passed_count"], 1 if "hard" in levels else 0)
            print(
                f"[local] progress {kp_key}: lit -> 1, lit_percent -> {percent}, "
                f"question_level -> {chosen_level}, counts -> "
                f"(easy={easy_count}, medium={medium_count}, hard={hard_count})"
            )
            if not dry_run:
                con.execute(
                    """
                    UPDATE progress_entries
                    SET lit = 1,
                        lit_percent = ?,
                        question_level = ?,
                        easy_passed_count = ?,
                        medium_passed_count = ?,
                        hard_passed_count = ?,
                        updated_at = CAST(strftime('%s', 'now') AS INTEGER)
                    WHERE id = ?
                    """,
                    (
                        percent,
                        chosen_level,
                        easy_count,
                        medium_count,
                        hard_count,
                        row["id"],
                    ),
                )
            rows_changed += 1

        if not dry_run:
            con.commit()
        print(f"[local] migrated {rows_changed} rows")
        return rows_changed
    finally:
        con.close()


def run_remote_mysql(
    *,
    ssh_key: Path,
    remote_user: str,
    remote_host: str,
    mysql_user: str,
    mysql_password: str,
    mysql_host: str,
    mysql_db: str,
    sql: str,
) -> subprocess.CompletedProcess[str]:
    remote_cmd = (
        f"/usr/bin/mysql -N -B -u{shlex.quote(mysql_user)} "
        f"-p{shlex.quote(mysql_password)} "
        f"-h{shlex.quote(mysql_host)} "
        f"{shlex.quote(mysql_db)}"
    )
    return subprocess.run(
        [
            "ssh",
            "-i",
            str(ssh_key),
            f"{remote_user}@{remote_host}",
            remote_cmd,
        ],
        input=sql,
        text=True,
        capture_output=True,
        check=False,
    )


def migrate_server_mysql(
    *,
    ssh_key: Path,
    remote_user: str,
    remote_host: str,
    mysql_user: str,
    mysql_password: str,
    mysql_host: str,
    mysql_db: str,
    dry_run: bool,
) -> int:
    select_sql = """
    SELECT id, student_user_id, course_id, kp_key, summary_text
    FROM progress_sync
    WHERE summary_text REGEXP 'PASS_(EASY|MEDIUM|HARD)';
    """
    result = run_remote_mysql(
        ssh_key=ssh_key,
        remote_user=remote_user,
        remote_host=remote_host,
        mysql_user=mysql_user,
        mysql_password=mysql_password,
        mysql_host=mysql_host,
        mysql_db=mysql_db,
        sql=select_sql,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"Remote MySQL select failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )
    rows = []
    for line in result.stdout.splitlines():
        parts = line.split("\t", 4)
        if len(parts) != 5:
            continue
        row_id, student_user_id, course_id, kp_key, summary_text = parts
        level = level_from_mastery(summary_text)
        if level is None:
            continue
        rows.append((int(row_id), int(student_user_id), int(course_id), kp_key, level))
    if not rows:
        print("[server] no legacy summary rows found in progress_sync")
        return 0
    print(f"[server] found {len(rows)} legacy progress_sync rows")
    rows_changed = 0
    update_sql_parts = []
    for row_id, student_user_id, course_id, kp_key, level in rows:
        percent = percent_for_level(level)
        print(
            f"[server] progress_sync id={row_id} student={student_user_id} "
            f"course={course_id} kp={kp_key}: lit -> 1, lit_percent -> {percent}, "
            f"question_level -> {level}"
        )
        update_sql_parts.append(
            "UPDATE progress_sync "
            f"SET lit = 1, lit_percent = {percent}, question_level = '{level}', updated_at = UTC_TIMESTAMP() "
            f"WHERE id = {row_id};"
        )
        rows_changed += 1
    if dry_run:
        print(f"[server] dry-run only; would update {rows_changed} rows")
        return rows_changed
    update_sql = "\n".join(update_sql_parts)
    update_result = run_remote_mysql(
        ssh_key=ssh_key,
        remote_user=remote_user,
        remote_host=remote_host,
        mysql_user=mysql_user,
        mysql_password=mysql_password,
        mysql_host=mysql_host,
        mysql_db=mysql_db,
        sql=update_sql,
    )
    if update_result.returncode != 0:
        raise RuntimeError(
            f"Remote MySQL update failed:\nSTDOUT:\n{update_result.stdout}\nSTDERR:\n{update_result.stderr}"
        )
    print(f"[server] migrated {rows_changed} rows")
    return rows_changed


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--local-db", type=Path, default=default_local_db_path())
    parser.add_argument("--skip-local", action="store_true")
    parser.add_argument("--skip-server", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--remote-host", default="43.99.59.107")
    parser.add_argument("--remote-user", default="ecs-user")
    parser.add_argument("--ssh-key", type=Path, default=Path(r"C:\Users\kl\.ssh\id_rsa"))
    parser.add_argument("--mysql-user", default="ftapp")
    parser.add_argument("--mysql-password", default="FtApp_2026!p7Lz")
    parser.add_argument("--mysql-host", default="127.0.0.1")
    parser.add_argument("--mysql-db", default="family_teacher")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    total_changed = 0
    if not args.skip_local:
        total_changed += migrate_local_sqlite(args.local_db, args.dry_run)
    if not args.skip_server:
        total_changed += migrate_server_mysql(
            ssh_key=args.ssh_key,
            remote_user=args.remote_user,
            remote_host=args.remote_host,
            mysql_user=args.mysql_user,
            mysql_password=args.mysql_password,
            mysql_host=args.mysql_host,
            mysql_db=args.mysql_db,
            dry_run=args.dry_run,
        )
    print(f"[done] total rows touched: {total_changed}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
