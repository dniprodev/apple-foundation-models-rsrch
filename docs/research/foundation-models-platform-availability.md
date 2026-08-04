# Foundation Models platform and regional availability

Research snapshot: **2026-08-05**. This report extends the platform-availability portion of [Verify Foundation Models and Claude integration constraints](https://github.com/dniprodev/apple-foundation-models-rsrch/issues/2). It separates Apple's on-device `SystemLanguageModel` from Anthropic's remote Claude provider because they have different OS, hardware, authentication, and regional gates.

Versions checked:

- **Apple toolchain:** Xcode 27 beta 4, iOS/iPadOS/macOS 27 SDKs, Swift 6.4. Apple's current requirements table was checked on 2026-08-05. [Apple Xcode SDK and system requirements](https://developer.apple.com/xcode/system-requirements)
- **Anthropic package:** latest release tag **0.1.4** (`410f5e4546fa0f9bd8bb926b77257725af81c9f7`); current `main` inspected at [`98a74ff`](https://github.com/anthropics/ClaudeForFoundationModels/tree/98a74ff2300996ff192062c25114aea8c4103d2b), one commit after that tag. Its manifest uses Swift tools 6.2 and declares iOS, macOS, visionOS, and watchOS 27. [Anthropic `Package.swift`](https://github.com/anthropics/ClaudeForFoundationModels/blob/98a74ff2300996ff192062c25114aea8c4103d2b/Package.swift) · [Anthropic README requirements](https://github.com/anthropics/ClaudeForFoundationModels/blob/98a74ff2300996ff192062c25114aea8c4103d2b/README.md#requirements)

## Decision summary

| Configuration | Build/install | Apple on-device model | Claude through `ClaudeForFoundationModels` |
| --- | --- | --- | --- |
| Apple-silicon Mac, macOS 26.5, Xcode 27 beta 4 | **Yes.** Xcode requires macOS 26.4 or later. | **Yes as a host/runtime**, if Apple Intelligence is enabled, ready, and configured for a supported language/region. | **Build yes; run in an iOS 27 simulator with API-key auth.** Exact local-model behavior in the iOS 27 simulator on a 26.5 host still needs a smoke test. |
| Eligible iPhone on iOS 26.4 | A local-only app can install if its deployment target is 26.4 or lower. | **Yes.** Apple documents a specific 26.4 system-model generation. | **No.** The package and server-provider API require iOS 27. |
| Any other iPhone on iOS 26.4 | The app may install if its deployment target permits it. | **No** if it is not an Apple Intelligence-eligible model. | **No** with the current package because the OS is below iOS 27. |
| iPad app on Apple-silicon Mac running macOS 26.5 | Apple supports unmodified iPhone/iPad apps on Apple-silicon Macs, but computes the actual Mac minimum from the submitted build. | The OS 26-era framework has been reported to work as “Designed for iPad,” but this exact app must be tested. | **Do not claim support on 26.5.** The iOS package floor is 27 and Apple does not publish the iOS-27-to-macOS compatibility mapping used for this distribution mode. Treat macOS 27 as the safe floor until an archive/App Store Connect and runtime test prove otherwise. |

For the stated setup, **macOS 26.5 + Xcode 27 beta is OK; an iPhone on iOS 26.4 is not OK for the planned full Apple/Claude integration.** That phone remains useful for a local-only, iOS-26-compatible path if it is an iPhone 15 Pro/Pro Max or iPhone 16 or later and its runtime availability check succeeds.

## Compile and install requirements

### Apple's on-device Foundation Models API

The original Foundation Models framework shipped in the OS 26 SDK generation, so **Xcode 26 is the practical minimum** for an app that uses only the original on-device API. Apple describes the framework as available on iOS, iPadOS, macOS, and visionOS 26, and its current `SystemLanguageModel` documentation identifies distinct model generations for OS 26.0–26.3, OS 26.4, and OS 27. [WWDC25 framework introduction](https://developer.apple.com/videos/play/wwdc2025/286/) · [Apple `SystemLanguageModel`](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)

Xcode 27 beta 4 runs on **macOS 26.4 or later**, includes the iOS 27 SDK, can deploy apps whose targets span iOS/iPadOS 15–27, and can debug physical devices or simulators on iOS 17 or later. Therefore **Xcode 27 beta on macOS 26.5 is an Apple-supported toolchain combination**, and it can connect to an iOS 26.4 phone. Xcode 27 itself runs only on Apple-silicon Macs. Connecting/debugging a phone does not prove that an app's deployment target or dependencies permit installation. [Apple Xcode SDK and system requirements](https://developer.apple.com/xcode/system-requirements) · [Xcode 27 beta release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes)

An app built with Xcode 27 can still target iOS 26.4 if it uses only APIs available there and availability-gates newer APIs. In particular, the on-device `SystemLanguageModel` path can target iOS 26, while new OS-27 Foundation Models features need `if #available(iOS 27, *)` or a separate OS-27 target. This is a normal SDK/deployment-target distinction, not a promise that the model is ready at runtime.

### Anthropic's Claude provider

Anthropic's current package targets the **server-side `LanguageModel` provider API introduced in OS 27** and explicitly requires **Xcode 27 beta plus iOS/macOS/visionOS/watchOS 27**. SwiftPM will raise the consuming target's effective platform requirement; availability checks cannot make this package installable on iOS 26.4. [Anthropic README requirements](https://github.com/anthropics/ClaudeForFoundationModels/blob/98a74ff2300996ff192062c25114aea8c4103d2b/README.md#requirements) · [Anthropic `Package.swift`](https://github.com/anthropics/ClaudeForFoundationModels/blob/98a74ff2300996ff192062c25114aea8c4103d2b/Package.swift) · [Apple provider-package example](https://developer.apple.com/videos/play/wwdc2026/339/)

Consequently, supporting the iOS 26.4 phone would require a deliberately separate local-only product/target or postponing the Claude package on that OS. The planned common-session hybrid app has an **iOS/iPadOS 27 minimum**.

## Runtime availability of Apple's on-device model

Compile/install success is insufficient. Before presenting the feature, the app must read `SystemLanguageModel.default.availability`. Apple's documented unavailable reasons are: Apple Intelligence is disabled, the device is ineligible, or model assets are not ready. Model assets download automatically depending on network, battery, and system load. [Apple availability reasons](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/availability-swift.enum/unavailablereason) · [Apple `modelNotReady`](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/availability-swift.enum/unavailablereason/modelnotready)

### Eligible hardware

Apple's current hardware rules are exact by chip/family:

- **iPhone:** iPhone 15 Pro and iPhone 15 Pro Max; every iPhone 16 model or later. A base iPhone 15/15 Plus and older phones are ineligible.
- **iPad:** iPad mini with A17 Pro, plus iPad models with M1 or later. This includes M-series iPad Air/Pro; an A16 iPad is ineligible.
- **Mac:** any Mac with Apple silicon. Intel Macs are ineligible.

These are Apple Intelligence eligibility rules, which Apple links from the Foundation Models documentation. [Apple Intelligence device requirements](https://support.apple.com/en-gb/121115) · [Apple Foundation Models overview](https://developer.apple.com/documentation/foundationmodels/)

### Storage, settings, model, and language

Eligible hardware also needs all of the following:

- Apple Intelligence enabled in Settings;
- **7 GB** of available on-device storage for Apple Intelligence assets;
- device language and Siri language set to the **same supported language**;
- the requested model assets fully downloaded and ready.

Apple recommends Wi-Fi and power while the assets download. Turning Apple Intelligence off removes the on-device models. The framework's supported language set can change with OS/model updates; code should call `supportsLocale(_:)` and handle `unsupportedLanguageOrLocale` rather than hard-code the current list. [Apple Intelligence setup requirements](https://support.apple.com/en-gb/121115) · [Apple language and locale guidance](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models)

As of this snapshot, Apple's listed languages for iOS/iPadOS/macOS 26.1 and later are English, Danish, Dutch, French, German, Italian, Norwegian, Portuguese, Spanish, Swedish, Turkish, Simplified Chinese, Traditional Chinese, Japanese, Korean, and Vietnamese. **Ukrainian is not listed.** A user in Ukraine should select matching supported device/Siri languages, such as English, to use the on-device model. [Apple Intelligence supported languages and regions](https://support.apple.com/en-gb/121115)

## Simulator support and host requirements

Apple supports exercising `SystemLanguageModel` in iPhone and visionOS simulators. The simulator uses the model assets and compute of the **host Mac**, not a simulated target-device model. The host therefore needs:

- an Apple-silicon Mac;
- macOS 26 or later for the OS-26 model generation;
- Apple Intelligence enabled and model assets ready on the host;
- a supported host language/region configuration;
- an internal startup volume; Apple Intelligence is unavailable in a macOS virtual machine and when the Mac is started from the external-volume configuration documented by Apple DTS.

Simulator measurements reflect the Mac, so they are suitable for functional prompt iteration but not iPhone/iPad latency, memory, energy, or thermal validation. [Apple Foundation Models code-along](https://developer.apple.com/videos/play/wwdc2025/259/) · [Apple DTS simulator/host checklist](https://developer.apple.com/forums/thread/787445)

Xcode 27 beta 4 on macOS 26.5 is documented to run an iOS 27 simulator. However, Apple's explicit “simulator uses the host model” guidance predates the OS-27 model generation. Whether an iOS 27 simulator on a macOS 26.5 host correctly exercises every new OS-27 local-model behavior is therefore a **required empirical test**, not a documented guarantee.

Claude has a separate simulator story: Anthropic explicitly supports **API-key authentication for simulator development**. App Attest requires a physical device and Secure Enclave and throws `attestationUnsupported` in Simulator. A bundled API key is extractable and must not ship. The remote Claude call does not use the host's Apple on-device model, but it still requires an OS-27 simulator because the package's provider interface is OS-27-only. [Anthropic authentication guidance](https://github.com/anthropics/ClaudeForFoundationModels/blob/98a74ff2300996ff192062c25114aea8c4103d2b/README.md#authentication)

## Running the iPad app on a Mac

Apple permits an unmodified iPhone/iPad binary to run as an **iOS App on Mac** on Apple-silicon Macs; it is a real iOS app on Mac, not Simulator or Mac Catalyst. The generic mechanism starts at macOS 11, but that is not the minimum for this app. App Store Connect calculates a build's actual minimum macOS from `LSMinimumSystemVersion` and the macOS version corresponding to the build's iOS `MinimumOSVersion`, and the developer can choose a higher floor. [Apple: Running iOS apps in macOS](https://developer.apple.com/documentation/apple-silicon/running-your-ios-apps-in-macos) · [App Store Connect availability rules](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-of-iphone-and-ipad-apps-on-macs-with-apple-silicon)

For a **local-only OS-26 build**, the practical Foundation Models runtime floor is macOS 26 on an eligible Apple-silicon Mac with Apple Intelligence ready. An Apple Developer Forums report says Foundation Models worked in “Designed for iPad” mode, but Apple has not published a Foundation Models compatibility contract specifically for this distribution mode. Test the archive on the intended Mac before declaring support. [Apple DTS thread](https://developer.apple.com/forums/thread/787445)

For the **full Claude package**, native macOS support explicitly starts at macOS 27 and the iOS package platform starts at iOS 27. Apple does not publish the iOS-27-to-macOS version correspondence App Store Connect applies to an iOS App on Mac. Therefore **macOS 26.5 is not a supportable promise for the full hybrid iPad binary**; use macOS 27 as the conservative minimum until App Store Connect reports the submitted build's computed floor and the binary passes a real-Mac test.

Mac Catalyst is a different build product and should not be used as evidence for iOS App on Mac compatibility. If a Catalyst product is desired, compile and test it separately.

## Region and account constraints

### Apple on-device model

Apple says Apple Intelligence is available in most regions worldwide. For EU residents, most Apple Intelligence features have been available on eligible iPhone/iPad hardware since iOS/iPadOS 18.4 and on eligible Macs since macOS 15.1. Apple's current explicit regional/account restriction concerns China mainland; it does not name Ukraine as restricted. [Apple Intelligence supported regions](https://support.apple.com/en-gb/121115)

Therefore:

- **European Union:** no Foundation Models-specific EU block is documented. Normal device, settings, model, OS, and language gates still apply.
- **Ukraine:** Apple does not explicitly list Ukraine country/account region support, but “most regions worldwide” plus the absence of a Ukraine exception supports the inference that the on-device model is available there. This remains an inference to confirm on the target device. Ukrainian language itself is currently unsupported, so use matching supported device/Siri languages.
- **China mainland:** preserve Apple's device-purchase, physical-location, and Apple Account country/region rules; those are the documented geographic exception.

Because the local model runs on-device and can work offline, Anthropic's country policy does not control `SystemLanguageModel`. Always use the runtime availability API as the final authority for a particular device. [WWDC25 Foundation Models introduction](https://developer.apple.com/videos/play/wwdc2025/286/) · [Apple `SystemLanguageModel`](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)

### Anthropic / Claude

Claude is remote and governed independently by Anthropic's Supported Regions Policy. Anthropic currently lists commercial API access across Europe and explicitly lists **Ukraine except Crimea, Donetsk, Kherson, Luhansk, and Zaporizhzhia regions**. It also reserves the right not to serve entities whose majority direct or indirect ownership is attributable to countries outside its supported list. [Anthropic supported countries and regions](https://www.anthropic.com/supported-countries)

Apple Intelligence being enabled, the Apple Account region, and Apple's supported Siri languages are not documented prerequisites for an Anthropic API request. Claude instead needs an OS-27 app, network access, a supported Anthropic region, and valid package authentication. API-key authentication works in Simulator/development; production should use Anthropic App Attest on supported physical hardware or an app-owned proxy. The current package does not expose a preflight country-eligibility API, so regional denial must be handled as an authentication/provider failure.

## Required empirical acceptance tests

Documentation does not close the following beta/runtime gaps. Run and record one minimal response for each configuration:

1. **Toolchain/package:** resolve and compile `ClaudeForFoundationModels` 0.1.4/current pinned commit with the exact installed Xcode 27 beta seed on macOS 26.5.
2. **Simulator:** run one local response and one API-key Claude response in an iOS 27 simulator; record the host Mac chip, startup volume, macOS build, Apple Intelligence state, Xcode build, simulator runtime, and `SystemLanguageModel.default.availability`.
3. **iOS 26.4 phone:** use a local-only target, record the exact iPhone model and availability enum, and run one local response. Do not expect the Claude package to install.
4. **iOS App on Mac:** archive the iPad app, inspect App Store Connect's computed minimum macOS, then run it on the intended Apple-silicon Mac. Test the local model on macOS 26.5; test the full hybrid build on macOS 27 unless the submitted-build metadata proves a lower compatible floor.
5. **Ukraine:** on a target device physically in Ukraine with a Ukraine Apple Account region, use matching supported languages, record local-model availability, and make one Claude API request from a permitted Ukrainian region.
6. **Production authentication:** validate App Attest on the actual physical OS-27 device. Simulator success with an API key does not cover this path.

## Confidence boundary

The Xcode host matrix, Anthropic package platform floors, Apple Intelligence hardware/storage/language requirements, generic iOS App on Mac mechanism, and Anthropic's Ukraine exclusions are documented facts. The Apple on-device model's availability in Ukraine is a strong inference rather than a country-specific Apple statement. The exact iOS 27 simulator/local-model behavior on macOS 26.5 and the minimum macOS computed for this iOS-27 iPad binary require empirical verification. Beta SDK and model behavior can change between seeds.
