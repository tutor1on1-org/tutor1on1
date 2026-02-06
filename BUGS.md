# Bugs / Issues Encountered
Last updated: 2026-02-06

- 2026-01-31 - `:app:processReleaseResources` failed with `java.nio.charset.MalformedInputException: Input length = 1`. It's due to the encryption software. The files are likely in .\build\app\intermediates\*.txt.
