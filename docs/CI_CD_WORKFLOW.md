# STOP Vanthachu — CI/CD Pipeline & GitHub Automation

**Pipeline Configuration:** `.github/workflows/ci.yml`  
**CI Platform:** GitHub Actions  
**Host Runner:** `ubuntu-latest`  
**Quality Enforcement:** Zero Static Analysis Errors + 100% Passing Automated Tests + Successful Android APK Compilation

---

## 1. Overview & Pipeline Philosophy

STOP Vanthachu employs an automated Continuous Integration and Continuous Delivery (CI/CD) workflow that enforces strict quality gates on every code change before it merges into `main`.

The pipeline executes three critical validations sequentially:
1. **Lint & Code Analysis:** Enforces Flutter/Dart best practices and zero analyzer issues via `flutter analyze`.
2. **Automated Verification:** Runs the complete suite of 134 automated unit, widget, and integration tests via `flutter test`.
3. **Reproducible Compilation:** Compiles the complete Android application package (`flutter build apk --debug`) and archives the resulting APK binary as a downloadable build artifact.

---

## 2. Trigger Events

The workflow triggers automatically on:
- **Push events** targeting the `main` branch.
- **Pull Request events** targeting the `main` branch.
- **Manual Trigger (`workflow_dispatch`)** via the GitHub Actions web interface for on-demand builds and testing.

---

## 3. Workflow Steps & Quality Gates

```mermaid
flowchart LR
    Trigger[Push / PR to main] --> Checkout[actions/checkout@v4]
    Checkout --> Java[setup-java@v4 Temurin 17]
    Java --> Flutter[flutter-action@v2 Stable]
    Flutter --> PubGet[flutter pub get]
    PubGet --> Analyze{flutter analyze}
    Analyze -- Pass --> Test{flutter test}
    Analyze -- Fail --> Block[Block PR / Fail Build]
    Test -- Pass --> Build[flutter build apk --debug]
    Test -- Fail --> Block
    Build --> Artifact[upload-artifact@v4 app-debug.apk]
```

### Detailed Job Execution: `verify-and-build`

| Step | Action / Command | Expected Standard | Failure Impact |
| :--- | :--- | :--- | :--- |
| **Checkout** | `actions/checkout@v4` | Full repository checkout | Build aborted |
| **Java Setup** | `actions/setup-java@v4` | OpenJDK Temurin 17 LTS | Gradle failure |
| **Flutter Setup**| `subosito/flutter-action@v2` | Latest stable Flutter channel with package caching | Environment mismatch |
| **Dependencies** | `flutter pub get` | Resolves all pub dependencies cleanly | Missing symbols |
| **Static Analysis**| `flutter analyze` | **0 warnings, 0 errors, 0 lints** | **Build strictly fails** |
| **Test Matrix** | `flutter test` | **100% tests passing** (134/134) | **Build strictly fails** |
| **APK Build** | `flutter build apk --debug` | Successful generation of `app-debug.apk` | Build failure |
| **Artifact Save**| `actions/upload-artifact@v4` | Retention for 14 days | Warning |

---

## 4. Local Execution Equivalents

Developers can run the exact verification pipeline locally before pushing commits:

```bash
# 1. Fetch dependencies
flutter pub get

# 2. Run static analysis (must report: No issues found!)
flutter analyze

# 3. Run full automated test suite (must report: All tests passed!)
flutter test

# 4. Verify Android debug build
flutter build apk --debug
```

---

## 5. Artifact Distribution

Upon successful workflow completion:
- The compiled APK (`app-debug.apk`) is packaged into a downloadable zip file named `stop-vanthachu-app-debug`.
- The artifact is available directly in the GitHub Actions run summary under **Artifacts** for 14 days.
- Testers and contributors can download and side-load the APK directly onto Android test devices without requiring a local development environment.
