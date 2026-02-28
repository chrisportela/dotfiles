# React Native (bare) + pnpm Template

A bare React Native project template with TypeScript, pnpm, and Nix flakes for a reproducible development environment.

## Features

- React Native (bare) with TypeScript
- pnpm with `node-linker=hoisted` (required for RN)
- Nix flake dev shell: Node.js, Android SDK, JDK, watchman; on macOS: CocoaPods, Xcode; on Linux: Android Studio
- React Navigation (bottom tabs + native stack)
- Jest for unit tests
- Writable Android SDK overlay in the Nix shell (avoids read-only store issues)

## Template maintainers

To regenerate the lockfile (e.g. after changing `package.json`), run from this directory:

```bash
nix develop --command pnpm install
```

Then commit `pnpm-lock.yaml`.

## Prerequisites

- [Nix](https://nixos.org/download.html) with flakes enabled
- [direnv](https://direnv.net/) (optional, for automatic shell activation)
- For native builds: Android emulator or iOS Simulator

## Getting Started

### 1. Create the project from the template

```bash
nix flake new my-app -t github:chrisportela/dotfiles#react-native
cd my-app
```

Or from a local dotfiles clone:

```bash
nix flake new my-app -t /path/to/dotfiles#react-native
cd my-app
```

### 2. Activate the Nix environment

```bash
direnv allow
```

Or enter the shell manually:

```bash
nix develop
```

### 3. Generate native projects (one-time)

Pick your app name (e.g. `MyApp`). This creates `android/` and `ios/` and updates `app.json`:

```bash
chmod +x setup.sh   # if needed
./setup.sh MyApp
```

### 4. Install dependencies

```bash
pnpm install
```

### 5. iOS: install Ruby gems and pods (macOS only)

If you build for iOS, Bundler and CocoaPods use the project Gemfile:

```bash
bundle install
cd ios && bundle exec pod install && cd ..
```

### 6. Run the app

- **Metro (JS only):** `pnpm start`
- **Android:** `pnpm android` (requires Android SDK and emulator)
- **iOS (macOS only):** `pnpm ios` (requires Xcode and simulator)

### 7. Run tests

```bash
pnpm test
```

## Project structure

```
.
├── App.tsx                 # Root component (NavigationContainer + RootNavigator)
├── index.js                # Entry point (AppRegistry)
├── app.json                # App name / display name (updated by setup.sh)
├── src/
│   ├── navigation/         # RootNavigator (tabs + stack)
│   ├── screens/            # Home, Details, Settings
│   └── components/        # Section, etc.
├── __tests__/              # Jest tests
├── setup.sh                # Generates android/ and ios/
├── flake.nix               # Nix dev shell
├── package.json
├── tsconfig.json
├── babel.config.js
├── metro.config.js
└── jest.config.js
```

## Scripts

| Script       | Description                    |
|-------------|--------------------------------|
| `pnpm start`  | Start Metro bundler            |
| `pnpm android`| Run on Android                 |
| `pnpm ios`    | Run on iOS (macOS)             |
| `pnpm test`   | Run Jest tests                 |
| `pnpm lint`   | Run ESLint                     |

## Nix shell

The flake provides a `devShell` with:

- Node.js 22, pnpm, watchman
- JDK 17 (Zulu), Android SDK (via android-nixpkgs), Gradle
- On macOS: CocoaPods, Xcode 16.2
- On Linux: Android Studio

On first enter, the shell copies the Android SDK to a writable `.android-sdk/` in the project so Gradle can write caches. Add `.android-sdk/` to `.gitignore` (already ignored).

## Customization

- **App name:** Run `./setup.sh YourAppName` before or after cloning; this updates `app.json` and (if run before moving android/ios) the native projects.
- **Navigation:** Edit `src/navigation/RootNavigator.tsx` (tabs and stacks).
- **Screens:** Add screens under `src/screens/` and register them in the navigators.

## Learn more

- [React Native](https://reactnative.dev/)
- [React Navigation](https://reactnavigation.org/)
- [Nix Flakes](https://nixos.wiki/wiki/Flakes)
- [direnv](https://direnv.net/)
