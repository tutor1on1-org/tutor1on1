FAMILY TEACHER - PROJECT README

OVERVIEW
Family Teacher is a Flutter desktop app (Windows-first) for teacher-managed tutoring with a skill tree, sessions, and LLM-backed chat.

REPO ROOT
This project lives in: C:amily_teacherpp

REQUIREMENTS
- Flutter SDK >= 3.4
- Windows build tools (Visual Studio C++ toolchain)
- Python (optional, for helper scripts like temp.py)

RUN (WINDOWS)
1) flutter pub get
2) flutter gen-l10n
3) flutter run -d windows

BUILD (WINDOWS)
- flutter build windows
- The executable is in build\windowsdunner\Releaseamily_teacher.exe

ENVIRONMENT VARIABLES (OPTIONAL)
- OPENAI_API_KEY
- OPENAI_BASE_URL
- OPENAI_MODEL

DATA LOCATIONS
- SQLite DB: %USERPROFILE%\Documentsamily_teacher.db
- API keys: OS secure storage (not in SQLite)
- Course materials: teacher-selected folder on disk

COURSE FOLDER FORMAT (CURRENT)
- contents.txt or context.txt at the root
- {id}_lecture.txt (required)
- {id}_easy.txt, {id}_medium.txt, {id}_hard.txt (optional)

NOTES
- Prompts are stored in assets/teachers/<teacher>/prompts/*.txt
- Learn prompt can be edited from the Prompt Templates page.
