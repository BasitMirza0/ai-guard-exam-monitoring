# Security, privacy and publication

## Scope and publication policy

Real Firebase project configuration, signing keys, logs, environment files,
private media, models, Python environments and generated caches stay local.
`.gitignore` is a convenience, not a secret-removal mechanism for already-tracked
files. No credentials, GitHub repository, remote push, history rewrite or model
publication were created by this audit.

Firebase API keys identify the project; they do not authorize access to data.
Protect data with Firebase Security Rules and appropriate API restrictions/App
Check. This project's publication policy nevertheless excludes its actual Firebase
config to avoid coupling a public clone to a real project.
[Firebase guidance](https://firebase.google.com/docs/projects/api-keys).

## Current findings and boundaries

The inspected Git repository had no HEAD, refs, reflog entries or tracked files.
It did contain 34,143 unreachable blob objects and leftover temporary objects,
including a Firebase-configuration blob and dependency/environment material.
There were no commit objects, so no author/committer history to sanitize. Do not
copy this `.git` directory into a public repository. Do not run destructive
cleanup/history commands as part of publication preparation.

The full text scan found Firebase configuration in ignored local files/generated
outputs, personal information in debug logs and machine paths in generated files.
Private-key/token-like patterns in dependency code were library format markers,
examples or false positives, not identified application credentials. No ngrok
authtoken, GitHub PAT, application password or service-account private key was
identified in first-party publication candidates. Values are intentionally not
included here. The local signing keystore remains ignored and was not opened.

The scan is heuristic: binary files, model files, keystores and oversized text
require separate review; it cannot prove the absence of unknown secret formats.
The source-only snapshot excludes those artifacts. Branding/icon binary assets
are retained; no real screenshots were found. Exact scan/check evidence is in
[the audit report](AUDIT_REPORT.md); retained binary paths, sizes and purpose
are listed in the [binary asset inventory](BINARY_ASSETS.md).

## Runtime security that still needs verification

1. **Firestore rules:** not supplied or deployed here. Verify that pending users
   can create/read their own restricted profile, cannot self-approve or create
   admin roles, and cannot change protected identity/status fields. Only approved
   admins may approve/reject/change roles. Restrict incident reads by role and
   student ownership. Do not grant unrestricted client writes to `dvr_alerts`.
2. **Incident integrity:** the app submits client-generated metadata. A modified
   client can fabricate observations; this is not tamper-proof evidence.
3. **Remote API:** the client sends no Firebase ID token. The inspected backend
   has no authentication, authorization, rate limit, ownership check or durable
   queue. CORS allows all origins for Colab/ngrok demo use; this is not access
   control. Inputs now have 20 MiB/250 MiB bounds and safe generated temporary
   filenames; video suffix is checked and OpenCV must decode it. Successful
   outputs remain in `/tmp` without TTL or a deletion endpoint. Do not expose
   private exam media; this backend is not production-secure.
4. **Mobile permissions:** the app requests camera/internet; broad legacy storage
   and media-read permissions were removed because the picker uses platform
   selection. Release Android builds disallow cleartext HTTP; debug permits local
   development HTTP. Validate picker permission behavior on target devices.
5. **Identity:** use `demo@example.com`, a generic name and avatar for screenshots.
   Do not publish real student incidents or edit real users just for screenshots.
6. **Consent and review:** record only with informed consent and institutionally
   appropriate policies; state retention, access and deletion. Detections are
   probabilistic and must not independently determine disciplinary action.

## Colab secrets

Use `userdata.get("NGROK_AUTHTOKEN")` from Colab Secrets. Do not put the value in
notebook cells/outputs, `.env` tracked files, Flutter dart-defines or GitHub
workflow files. Do not print token values. See [Colab setup](../colab/README.md).

The backend imports Ultralytics and loads `/content/best_model_merged.pt` at
module import. PyPI identifies the Ultralytics package as AGPLv3-or-later; review
license compatibility before redistributing the backend. This does not establish
the license or rights for the separately trained weights.

## Clean publication procedure

`git archive HEAD` is unavailable because this development repository has no
commit. Use the included local-only snapshot helper instead:

```sh
python3 tool/prepare_publication.py --output publication/ai-guard-exam-monitoring
```

It copies tracked/unignored files without `.git`, refuses existing destinations,
rejects symlinks/large files, and blocks obvious secret patterns. Inspect its output
and run the validation steps again in the snapshot. The original development
folder, ignored configuration, models and object database stay intact. The
snapshot itself is ignored in the development folder.

Only **after your review and approval**, from the snapshot:

```sh
cd publication/ai-guard-exam-monitoring
git init -b main
git config user.name "YOUR_PUBLIC_NAME"
git config user.email "YOUR_GITHUB_NOREPLY_EMAIL"
git add .
git diff --cached --stat
git diff --cached --check
git commit -m "Prepare AI Guard portfolio project"
# Requires GitHub CLI authentication and your explicit publication decision:
gh repo create ai-guard-exam-monitoring --public --source=. --remote=origin
# Push is a separate deliberate action:
git push -u origin main
```

These commands are documentation only; no repository creation/commit/push has
been executed. Use your actual GitHub noreply address, not the placeholder.
The owner selected [AGPL-3.0](../LICENSE) for this publication snapshot. The
standard license text is included unchanged; third-party notices remain intact.
Model weights remain excluded. Check model/dataset and third-party rights for
your intended use; this source snapshot is not a legal compliance guarantee.
