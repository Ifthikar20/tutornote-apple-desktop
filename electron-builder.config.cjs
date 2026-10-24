/*
  How the app is packaged. `npm run dist:mac` on a Mac gives release/Tutornote-<version>-universal.dmg
  (drag-to-Applications installer), a .zip of the same app for the updater, and latest-mac.yml,
  the update feed. See the README for signing and notarising.
*/

// Notarise only when Apple credentials are in the environment (CI secrets); otherwise
// build unsigned so a developer can still package locally.
// The Mac speech helper (helpers/speech, built by scripts/build-speech-helper.sh into
// build/helpers): packaged into Contents/Resources when it was built, and signed with the
// app (electron-builder signs every binary it finds in the bundle, with the entitlements
// above, which include the microphone).
const speechHelper = require("node:path").join(__dirname, "build", "helpers", "tutornote-speech");
const hasSpeechHelper = require("node:fs").existsSync(speechHelper);

const notarize = Boolean(
  process.env.APPLE_ID && process.env.APPLE_APP_SPECIFIC_PASSWORD && process.env.APPLE_TEAM_ID,
);

/** @type {import("electron-builder").Configuration} */
module.exports = {
  appId: "app.tutornote.desktop",
  productName: "Tutornote",
  copyright: "Copyright © 2026 Tutornote",
  directories: {
    output: "release",
    buildResources: "build",
  },
  files: ["dist/**/*", "static/**/*", "renderer/**/*", "package.json"],
  asar: true,
  // Electron's own switches, burnt into the binary. As shipped they let any program on the
  // Mac run its code as this app (ELECTRON_RUN_AS_NODE, NODE_OPTIONS, --inspect) and so use
  // the microphone permission and the Keychain item the app was given, and they keep the
  // cookie store, the refresh cookie among it, in plain text on disk. Turned off, and the
  // cookies encrypted with a Keychain key, as Chrome does (one-way: cookies written once
  // encrypted cannot be read by a build without it). The app's code is checked against the
  // signed bundle when it loads, and is only ever app.asar. The file:// privileges stay: the
  // app's own screens (static/: the tab bar, the loading screen, sign-in, offline) are file://
  // pages inside app.asar, and with them off every one but sign-in failed to load
  // (ERR_FILE_NOT_FOUND) and the offline page retried itself in a loop. Electron's advice is
  // to turn them off only for an app that serves no file:// pages.
  electronFuses: {
    runAsNode: false,
    enableCookieEncryption: true,
    enableNodeOptionsEnvironmentVariable: false,
    enableNodeCliInspectArguments: false,
    enableEmbeddedAsarIntegrityValidation: true,
    onlyLoadAppFromAsar: true,
    grantFileProtocolExtraPrivileges: true,
  },
  // The link that brings a browser sign-in back into the app (src/main/auth.ts).
  protocols: { name: "Tutornote", schemes: ["anothernotes"] },
  publish: {
    provider: "github",
    owner: "Ifthikar20",
    repo: "Another-note-apple-desktop",
  },
  mac: {
    category: "public.app-category.education",
    target: [
      { target: "dmg", arch: ["universal"] },
      { target: "zip", arch: ["universal"] },
    ],
    icon: "build/icon.png",
    darkModeSupport: true,
    hardenedRuntime: true,
    gatekeeperAssess: false,
    entitlements: "build/entitlements.mac.plist",
    entitlementsInherit: "build/entitlements.mac.plist",
    notarize,
    extendInfo: {
      NSMicrophoneUsageDescription:
        "Tutornote uses the microphone so you can dictate notes and talk to the tutor.",
      NSSpeechRecognitionUsageDescription:
        "Tutornote uses speech recognition so the words you dictate appear as you say them.",
    },
    ...(hasSpeechHelper ? { extraResources: [{ from: speechHelper, to: "tutornote-speech" }] } : {}),
  },
  dmg: {
    title: "Tutornote",
    contents: [
      { x: 130, y: 220 },
      { x: 410, y: 220, type: "link", path: "/Applications" },
    ],
  },
  // Linux is a testing target only: it lets the packaging be exercised on a Linux box.
  linux: {
    target: ["AppImage"],
    category: "Education",
    icon: "build/icon.png",
  },
};
