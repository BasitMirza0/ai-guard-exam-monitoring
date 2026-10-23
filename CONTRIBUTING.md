# Contributing

This academic/portfolio project is released under [AGPL-3.0](LICENSE).
Third-party packages retain their original licenses.

- Preserve the existing exam, authentication and analysis flows and visual theme.
- Explain a reproducible bug or concrete improvement before a broad refactor.
- Never add credentials, real student media, logs, Firebase project files, model
  weights or notebook outputs. Use your own local configuration and demo identities.
- Keep raw detections distinct from accepted incidents. Do not claim model
  accuracy or supported detection modes without evidence.
- For fixes, add regression tests for meaningful failure cases and run:

```sh
flutter pub get
dart format --set-exit-if-changed .
flutter analyze
flutter test
python3 -m compileall -q tool
python3 tool/security_audit.py > /tmp/ai-guard-security.json
```

Review the scan findings locally; never paste secret values into an issue or PR.
The real backend source is in `backend/main.py`. Backend tests mock inference
and must not require private weights in CI. Run `pytest backend/tests -q` after
backend changes with the dependencies in `backend/requirements-test.txt`.
