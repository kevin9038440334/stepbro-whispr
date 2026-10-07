<p align="center">
  <img src="Resources/AppIcon.png" width="128" alt="stepbro whispr icon">
</p>

<h1 align="center">stepbro whispr</h1>

<p align="center">
  Voice dictation for macOS. Hold a key, speak, and clean text appears wherever you are typing.
</p>

<p align="center">
  <a href="https://github.com/kevin9038440334/stepbro-whispr/releases/latest"><img src="https://img.shields.io/github/v/release/kevin9038440334/stepbro-whispr?label=release&color=1f1f22" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-27%2B-1f1f22?logo=apple" alt="macOS 27 or later">
  <img src="https://img.shields.io/badge/Swift-6.4-1f1f22?logo=swift" alt="Swift 6.4">
  <a href="LICENSE.md"><img src="https://img.shields.io/badge/license-PolyForm%20Noncommercial-1f1f22" alt="License: PolyForm Noncommercial 1.0.0"></a>
</p>

<p align="center">
  <strong>English</strong> · <a href="README.es.md">Español</a>
</p>

---

stepbro whispr is a native macOS app written in Swift and SwiftUI, with a Liquid Glass interface. It is a free alternative to paid dictation tools such as Wispr Flow: it works in any app, keeps your own words, and fixes punctuation, lists and self-corrections for you.

You can run it fully on your Mac with Apple's speech recognition and Apple Intelligence, or connect your own Groq API key to use Whisper and larger language models in the cloud.

The interface is in Spanish. Dictation works in any language supported by Apple's speech recognizer.

## Features

- **Dictate anywhere.** Hold the hotkey (Fn by default), speak, release. The text is pasted at the cursor and your clipboard is restored afterwards.
- **Hands-free mode.** Double-tap the hotkey to keep recording without holding it, tap again to finish. Esc cancels at any point.
- **Your words, cleaned up.** Removes filler words and stutters, applies self-corrections ("at five, no, at six" becomes "at six"), and fixes misheard words from context, without paraphrasing.
- **Formatting.** Questions and exclamations (including Spanish ¿ and ¡), numbered and bulleted lists, spoken punctuation ("comma", "new paragraph"), emails and links.
- **Dictionary and snippets.** Names and terms that must always be spelled right, and short phrases that expand into longer text.
- **Style per app.** Casual in chat apps, formal in email, technical in code editors and terminals.
- **Context aware.** Reads the text before the cursor so a dictation can continue a sentence and match the names already written.
- **Long dictations.** With Groq, long recordings are split at natural pauses and transcribed while you are still talking, so the result is ready about a second after you stop.
- **Languages.** Dictate in any language supported by Apple's recognizer, switch between Spanish and English automatically, and optionally translate the result into another language.
- **History and stats.** Search past dictations, copy them again, and see your words per minute and time saved.

## Requirements

- macOS 27 or later on a Mac with Apple silicon.
- Optional: Apple Intelligence enabled, to polish text on device.
- Optional: a free API key from [console.groq.com](https://console.groq.com/keys), to use the Groq engine.

## Installation

1. Download the latest `.dmg` from [Releases](https://github.com/kevin9038440334/stepbro-whispr/releases/latest).
2. Open it and drag **stepbro whispr** into **Applications**.
3. Open the app. The first launch walks you through the microphone and Accessibility permissions, the hotkey and the language.

The app is not notarized by Apple, so macOS blocks it the first time. Go to **System Settings › Privacy & Security** and click **Open Anyway**. You only need to do this once.

If you keep Fn as the hotkey, set **System Settings › Keyboard › Press globe key to** to **Do Nothing** so the system does not react to it.

## Dictation engines

Choose one in **Ajustes › Motor de dictado** (Settings › Dictation engine).

| | Apple | Groq |
| --- | --- | --- |
| Speech recognition | `SpeechAnalyzer`, on device | Whisper Large v3 Turbo or v3 |
| Text polishing | Apple Intelligence, on device | Qwen 3.8 27B, GPT OSS 20B or 120B |
| Internet | Not needed | Required |
| Cost | Free | Free tier available |

With Groq, Apple's recognizer still runs in parallel as a fallback: if the network is slow or Groq fails, you still get your text. If the selected model reaches its rate limit, another one takes over.

## Privacy

- With the Apple engine, audio and text never leave your Mac.
- With Groq, the recorded audio and the text to polish are sent to Groq. If **Tener en cuenta lo ya escrito** (use the text before the cursor) is on, that snippet is sent too. Nothing is sent anywhere else.
- Your Groq key is stored in `~/Library/Application Support/stepbro whispr/`, readable only by your user.
- History, dictionary and settings stay on your Mac.

## Building from source

You need Xcode 27 (Swift 6.4).

```sh
git clone https://github.com/kevin9038440334/stepbro-whispr.git
cd stepbro-whispr
./scripts/create-certificate.sh   # once: a local signing certificate
make run                          # build and open build/stepbro whispr.app
```

| Command | What it does |
| --- | --- |
| `make build` | Builds and signs `build/stepbro whispr.app` |
| `make run` | Builds and opens the app |
| `make install` | Copies the app to `/Applications` |
| `make dmg` | Builds the installer `build/stepbro-whispr-<version>.dmg` |
| `make test` | Runs the unit tests |
| `make clean` | Removes build products |

A stable signing certificate lets macOS remember the app's permissions between builds. `scripts/build.sh` uses, in order, `SIGN_IDENTITY`, an "Apple Development" certificate, the local "Susurro Dev" certificate or an ad-hoc signature.

The bundle identifier is `com.susurro.Susurro`, from the project's original name. It is kept on purpose: changing it would make macOS treat the app as a different one and drop its permissions, history and settings.

## Project structure

```
Sources/StepbroWhisprCore/   Text logic with no UI, covered by tests
  SmartFormatter.swift         punctuation, lists, spoken commands, emails
  PolishPrompt.swift           model instructions and output safety checks
  GroqClient.swift             Groq API (Whisper and chat models)
  TranscriptChooser.swift      picks between the Whisper and Apple transcripts
  Vocabulary.swift             dictionary
  Snippets.swift               text snippets
  LongDictation.swift          joins the parts of a long dictation
  PauseDetector.swift          finds pauses to split long recordings
Sources/StepbroWhispr/
  App/     app lifecycle, coordination and preferences
  Audio/   microphone capture and speech recognition
  System/  global hotkey, paste, permissions, text before the cursor
  Text/    processing pipeline, Apple Intelligence, Groq, history
  UI/      main window, onboarding, floating bar
Tests/StepbroWhisprCoreTests/
scripts/   build, signing, icon and installer scripts
```

## License

stepbro whispr is source-available under the [PolyForm Noncommercial License 1.0.0](LICENSE.md).

You may use, study, modify and share it for any noncommercial purpose: personal use, study, hobby projects, and use by nonprofit, educational or public organizations. Selling it or using it for commercial purposes is not allowed. Any copy or modified version must keep the license and the `Required Notice` line with the author's credit.

For commercial use, contact the author through [GitHub](https://github.com/kevin9038440334).

## Authors

- [kevin9038440334](https://github.com/kevin9038440334)
- [srdavo](https://github.com/srdavo)
