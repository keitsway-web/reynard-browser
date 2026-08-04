# Reynard Project Development Guidelines

## Project Structure
- Main App: `browser/Reynard/`
- App Delegate: `browser/Reynard/AppDelegate.swift`
- Resources & Plist: `browser/Reynard/Resources/Info.plist`
- Entitlements:
  - Standard: `browser/Reynard/Entitlements/Reynard.entitlements`
  - TrollStore (Private): `browser/Reynard/Entitlements/Reynard.private.entitlements`
- Helper App Extension: `browser/Helper/`
- Build Scripts: `tools/release/build-app.sh`, `tools/release/create-ipa.sh`
- GitHub Actions Workflow: `.github/workflows/build.yml`

## Automated Fast Iteration Workflow
1. When user requests changes, make swift code/plist/entitlement modifications directly in `browser/Reynard/`.
2. Provide concise step-by-step git commands (`git add .`, `git commit -m "..."`, `git push origin main`) to push to the user's repository.
3. GitHub Actions uses `macos-14` (Apple Silicon M2) for ultra-fast build execution and packages `.tipa` automatically.
