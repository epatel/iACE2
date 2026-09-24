# Store listing drafts (App Store / Google Play)

## Name
iACE: Jupiter ACE emulator

## Subtitle / short description (≤ 30 / 80 chars)
- App Store subtitle: `The FORTH home computer`
- Play short description: `The 1982 Jupiter ACE, which ran FORTH, with its original manual built in.`

## Description
The Jupiter ACE was the odd one out among the home computers of the early 80s. Instead of BASIC it ran FORTH. Two members of the team behind the ZX81 and ZX Spectrum designed it in 1982.

iACE puts a Jupiter ACE on your tablet or phone, with its complete original user manual built in on tablets:

• The manual is built in. Tap the Enter buttons next to the examples and they are typed into the computer for you.
• A photo-real ACE keyboard, with SHIFT and SYMBOL SHIFT held just as on the real thing, or latched if you prefer.
• The ACE's beeper sound.
• SAVE and LOAD your FORTH dictionaries. Tapes are kept on the device and can be imported and exported as .TAP files, the format other ACE emulators use.
• Your session is kept when you leave the app.
• Frogger is included: type LOAD frogger, then VLIST.

The screen and keyboard slide down over the manual like drawers. Tap the manual to bring them down, and tap the screen to put them away.

iACE is free software under the GNU GPL: https://github.com/epatel/iACE2

"Jupiter ACE" is a trademark of Andrews UK Ltd.

## What's new in 2.0
iACE has been rebuilt from the ground up, and now runs on Android tablets as well as iPad:
• sound on every device
• .TAP tape import and export, and a tape browser
• volume control
• sharper graphics on every iPad size
Your saved tapes and settings from iACE 1.x are kept.

## Keywords (App Store, ≤ 100 chars)
jupiter ace,forth,emulator,retro,8-bit,z80,home computer,1982,programming

## Category
Education (secondary: Developer Tools)

## Privacy
No data is collected. The app has no network access of its own; it only opens links in the browser when you tap them. Policy: https://github.com/epatel/iACE2/blob/main/PRIVACY.md

Play Console data safety answers: no data collected, no data shared.

## Graphics (Google Play)

Made by `python3 tool/make_store_graphics.py`, from screenshots taken of the running app on the Android emulators. Those use portrait, Android demo mode for a clean status bar (10:00, full battery), and a 1080×2160 display for phones, because Play rejects screenshots longer than 2:1.

| Play Console field | File |
|---|---|
| App icon (512×512) | `store/graphics/icon-512.png` |
| Feature graphic (1024×500) | `store/graphics/feature-graphic.png` |
| Phone screenshots | `store/screenshots/phone-1-forth.png`, `phone-2-frogger.png`, `phone-3-settings.png` |
| 7-inch and 10-inch tablet screenshots | `store/screenshots/tablet-1-cover.png` … `tablet-5-settings.png` (1600×2560; the same set for both sizes) |

## Checklist before submitting
- [ ] iOS: signing team `67Y4XH38L7`, bundle `com.memention.iACE`, version 2.0.0 (build > the 1.2 build)
- [ ] Android: create the upload key with `make keystore` (then `make build-android`) and back up the keystore and its password
- [x] Privacy policy: https://github.com/epatel/iACE2/blob/main/PRIVACY.md
- [x] Screenshots for Android tablet and phone (portrait): `store/screenshots/`
- [ ] Screenshots: iPad 13" and 11", iPhone 6.9" and 6.1" (App Store)
- [ ] Note in the description that the manual view is tablet-only; phones link to the PDF
- [x] Public source code URL (GPL): https://github.com/epatel/iACE2 (in the About dialog)
- [x] ROM: Boldfield Computing (Paul Downham), who held the ACE rights after Jupiter Cantab, wrote in September 1998 that the ROM listing had been given away and that nobody would object to the emulator. The email is in [docs/legal/boldcomp.txt](../docs/legal/boldcomp.txt)
- [ ] Manual scan (Jupiter Ace Archive) and the "Jupiter ACE" name (trademark of Andrews UK Ltd): still to confirm
