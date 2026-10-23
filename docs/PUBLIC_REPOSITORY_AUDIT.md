# Public repository readiness audit

## Publication snapshot

The development Git database has no commit history, contains unreachable objects,
and must not be copied. Use the source-only helper to prepare a clean snapshot;
it excludes `.git`, ignored Firebase configuration, signing material, local logs,
models, Python environments, temporary media and publication output. Inspect the
snapshot's binary inventory and perform the manual review below before creating
a public repository. The helper does not create a commit or remote.

```sh
python3 -B tool/prepare_publication.py --output publication/ai-guard-exam-monitoring
cd publication/ai-guard-exam-monitoring
python3 -B tool/check_publication.py
python3 -B tool/security_audit.py
```

The report in [`AUDIT_REPORT.md`](AUDIT_REPORT.md) lists the latest local results.
See the [38-file binary inventory](BINARY_ASSETS.md) for retained icons, font,
launch artwork, sizes and purposes.
The scanner withholds matching values, but it is heuristic and skips binary
contents. No scan can replace reviewing retained graphics, font, plugin and
model licenses.

## Backend and model

The real source at `backend/main.py` is suitable for source review and its tests
mock YOLO. Do not copy model weights. They are loaded from
`/content/best_model_merged.pt` in the private Colab runtime. The Ultralytics
package is AGPLv3-or-later according to its [PyPI project page](https://pypi.org/project/ultralytics/);
review its current terms for your intended deployment. The owner has selected
[AGPL-3.0](../LICENSE) for this source publication snapshot. The unmodified GNU
license text is included, and third-party notices remain intact. Model-weight
rights and training-data rights remain unverified; weights are excluded.

The final license and documentation edits were applied to the existing snapshot.
Recreating it from the development folder alone will not preserve those edits.

## Manual publication checklist

- Review all files in the sanitized snapshot and confirm it contains no `.git`,
  Firebase private configuration, keys, credentials, personal media or model.
- Check third-party Flutter plugins/assets, retained binary assets, Ultralytics
  terms and model provenance/rights.
- Keep CORS wildcard and unauthenticated FastAPI use identified as Colab demo
  limitations. Do not send private exam media.
- Use genuine, sanitized screenshots only; no screenshot assets were fabricated.
- Do not publish or push until the owner explicitly chooses to do so.

Recommended fresh repository name: `ai-guard-exam-monitoring`.
