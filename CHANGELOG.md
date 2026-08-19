# Changelog

## [0.7.0](https://github.com/fireharp/mumbli/compare/v0.6.1...v0.7.0) (2026-08-19)


### Features

* compress dictation recordings to Opus, shrinking the archive 15.6x ([#35](https://github.com/fireharp/mumbli/issues/35)) ([ec65137](https://github.com/fireharp/mumbli/commit/ec6513741f94db6308af0e9cb48c9418a7e16703))
* replace the signed-receipts badge with dictation count + total duration ([#33](https://github.com/fireharp/mumbli/issues/33)) ([3d6502f](https://github.com/fireharp/mumbli/commit/3d6502ffa890c7e5b3c7d464bc738609022585a0))

## [0.6.1](https://github.com/fireharp/mumbli/compare/v0.6.0...v0.6.1) (2026-08-19)


### Bug Fixes

* store API keys in the real Keychain, delete recordings after success ([#29](https://github.com/fireharp/mumbli/issues/29)) ([a343cb9](https://github.com/fireharp/mumbli/commit/a343cb972567a98a1c1b5a412ef29bb5c198a3f6))

## [0.6.0](https://github.com/fireharp/mumbli/compare/v0.5.0...v0.6.0) (2026-08-18)


### Features

* add an app icon built from the site waveform ([#26](https://github.com/fireharp/mumbli/issues/26)) ([15decc6](https://github.com/fireharp/mumbli/commit/15decc693e4af668e5d1f50168e2c6ed3a92671f))
* give the DMG a designed drag-to-install window ([#24](https://github.com/fireharp/mumbli/issues/24)) ([4e48511](https://github.com/fireharp/mumbli/commit/4e48511db7dba5c2093bfa26c6803a8caa53849f))


### Bug Fixes

* keep dictations when Groq polishing fails ([#25](https://github.com/fireharp/mumbli/issues/25)) ([281b67b](https://github.com/fireharp/mumbli/commit/281b67b4b759b3d10de22e77f0305b34331f9f3e))
* show the real version and commit in Settings &gt; About ([#21](https://github.com/fireharp/mumbli/issues/21)) ([b97196e](https://github.com/fireharp/mumbli/commit/b97196e127e298ecef9ba18fdd623984ffeb3631))

## [0.5.0](https://github.com/fireharp/mumbli/compare/v0.4.0...v0.5.0) (2026-08-17)


### Features

* add verifiable usage proof for dictation ([#18](https://github.com/fireharp/mumbli/issues/18)) ([dd5736b](https://github.com/fireharp/mumbli/commit/dd5736b257beb619ec6e354497e3475f37a8260b))

## [0.4.0](https://github.com/fireharp/mumbli/compare/v0.3.3...v0.4.0) (2026-06-03)


### Features

* add Deepgram STT engine ([99550cf](https://github.com/fireharp/mumbli/commit/99550cf9158ddf2152154e30d007d60a0c646835))

## [0.3.3](https://github.com/fireharp/mumbli/compare/v0.3.2...v0.3.3) (2026-04-08)


### Bug Fixes

* Use system default input switch instead of audio unit device set ([177f79b](https://github.com/fireharp/mumbli/commit/177f79b173e4bbfe181c13beda1afc80d999132a))

## [0.3.2](https://github.com/fireharp/mumbli/compare/v0.3.1...v0.3.2) (2026-04-08)


### Bug Fixes

* Enable mic selection and reject silence before STT ([2a449ce](https://github.com/fireharp/mumbli/commit/2a449ce61b0ef30befc3dccf30711ededaca7053))

## [0.3.1](https://github.com/fireharp/mumbli/compare/v0.3.0...v0.3.1) (2026-04-08)


### Bug Fixes

* Strip hallucinated URLs from STT transcription output ([68437e4](https://github.com/fireharp/mumbli/commit/68437e46ff6f88f10cb9f6f3f1444cd3efde7c24))

## [0.3.0](https://github.com/fireharp/mumbli/compare/v0.2.0...v0.3.0) (2026-04-06)


### Features

* Add install script to bypass macOS Gatekeeper for unsigned app ([42d45e1](https://github.com/fireharp/mumbli/commit/42d45e1f8e37e5889761f65b0196884bdbb95d17))


### Bug Fixes

* Prevent double text injection in terminal apps ([d0d7eff](https://github.com/fireharp/mumbli/commit/d0d7effa4c3484a35c0ee3c325822e82fb319fd8))

## [0.2.0](https://github.com/fireharp/mumbli/compare/v0.1.2...v0.2.0) (2026-04-05)


### Features

* Add Mintlify documentation site with SEO pages ([#11](https://github.com/fireharp/mumbli/issues/11)) ([4770cf1](https://github.com/fireharp/mumbli/commit/4770cf1842ef63d9145251087453cc0a389eb6c1))

## [0.1.2](https://github.com/fireharp/mumbli/compare/v0.1.1...v0.1.2) (2026-04-03)


### Bug Fixes

* Correct versioning so feat bumps minor (0.x.0) not patch ([#7](https://github.com/fireharp/mumbli/issues/7)) ([3c111a9](https://github.com/fireharp/mumbli/commit/3c111a95449022563ddf5b6e7f1c4dffa647722f))

## [0.1.1](https://github.com/fireharp/mumbli/compare/v0.1.0...v0.1.1) (2026-04-03)


### Features

* Add automated release pipeline with DMG packaging ([#2](https://github.com/fireharp/mumbli/issues/2)) ([0c8b81b](https://github.com/fireharp/mumbli/commit/0c8b81b50a7aada2028e3949930e8a61e41180d0))
* Add custom vocabulary support ([#5](https://github.com/fireharp/mumbli/issues/5)) ([353ccf7](https://github.com/fireharp/mumbli/commit/353ccf745d394a65b0b4968bff1db7350db44d38))
* Add repetition guard and dictation wrapping ([#4](https://github.com/fireharp/mumbli/issues/4)) ([c307228](https://github.com/fireharp/mumbli/commit/c307228ccc58e643b5529fea66e6d03d9307ecef))
