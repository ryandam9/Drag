# Contributing to Drag

Thanks for helping improve Drag! This page covers the local setup, quality
gates, and release conventions that CI enforces.

## Toolchain

- **Flutter 3.44.2** (stable channel) — the version CI pins
  (`FLUTTER_VERSION` in `.github/workflows/ci.yml`). Other 3.x versions often
  work, but CI is the arbiter.
- A desktop platform toolchain for your OS (Xcode on macOS, Visual Studio C++
  workload on Windows, clang/CMake/ninja on Linux).

### Linux prerequisites

```bash
sudo apt-get install -y libsqlite3-dev libsecret-1-dev
```

- `libsqlite3-dev` — the history/connection stores use SQLite via
  `sqflite_common_ffi`.
- `libsecret-1-dev` — connection secrets are stored in the OS keychain
  (libsecret on Linux), never in SQLite.

For full desktop builds CI additionally installs
`ninja-build libgtk-3-dev clang cmake pkg-config libnotify-dev`.

## Running tests

```bash
flutter test
```

The suite is hermetic — no network, no credentials, no containers required.

**Coverage floor: 80% line coverage, enforced in CI** (`flutter test
--coverage`, then a check over `coverage/lcov.info`). If your change drops
coverage below the floor, add tests.

## Gated integration tests

Two end-to-end tests auto-skip unless pointed at a real server. They run in CI
(`s3-integration` and `sftp-integration` jobs) and you can reproduce them
locally with Docker.

### S3 (MinIO)

```bash
docker run -d --name minio -p 9000:9000 \
  -e MINIO_ROOT_USER=minioadmin -e MINIO_ROOT_PASSWORD=minioadmin \
  minio/minio server /data

# Create the two buckets the test expects.
docker run --rm --network host --entrypoint sh minio/mc -c \
  "mc alias set local http://127.0.0.1:9000 minioadmin minioadmin && \
   mc mb local/test-bucket local/test-bucket-b"

flutter test test/s3_integration_test.dart \
  --dart-define=S3_ENDPOINT=127.0.0.1:9000 \
  --dart-define=S3_BUCKET=test-bucket \
  --dart-define=S3_BUCKET2=test-bucket-b \
  --dart-define=S3_KEY=minioadmin \
  --dart-define=S3_SECRET=minioadmin

docker rm -f minio
```

(Add `--dart-define=S3_SSL=true` if your endpoint serves HTTPS; MinIO above is
plain HTTP.)

### SFTP

```bash
docker run -d --name sftp -p 2222:22 atmoz/sftp:alpine \
  sftptest:testpass123:::upload

flutter test test/sftp_integration_test.dart \
  --dart-define=SFTP_HOST=127.0.0.1 \
  --dart-define=SFTP_PORT=2222 \
  --dart-define=SFTP_USER=sftptest \
  --dart-define=SFTP_PASS=testpass123 \
  --dart-define=SFTP_DIR=/upload

docker rm -f sftp
```

## Formatting & analysis

CI rejects unformatted code and analyzer findings. Before pushing:

```bash
dart format .
flutter analyze
```

## Releases

Release tags are `v<version>` and **must match the `version:` in
`pubspec.yaml`** (the `+build` suffix is ignored for the comparison) — the
release workflow fails otherwise. Bump `pubspec.yaml` and add a `CHANGELOG.md`
entry in the same PR, then tag once it lands.
