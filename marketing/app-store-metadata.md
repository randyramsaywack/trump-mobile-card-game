# App Store Connect — Metadata (Copy / Paste)

All fields you'll be prompted for in App Store Connect, ready to paste.

---

## App Information

| Field | Value |
|---|---|
| **Name** | Trump |
| **Subtitle** (30 chars max) | `4-Player Trick-Taking Cards` |
| **Bundle ID** | com.randyland.trumpcardgame |
| **SKU** | trump-card-game |
| **Primary Language** | English (U.S.) |
| **Primary Category** | Games |
| **Secondary Category** | Card |
| **Content Rights** | No third-party content |

---

## Pricing and Availability

| Field | Value |
|---|---|
| **Price** | Free (USD 0 — Tier 0) |
| **Availability** | All countries and regions |
| **Pre-Order** | No |

---

## Promotional Text (170 chars max) — editable without new review
```
Deal. Call trump. Take your books. Trump is the classic 4-player card game you grew up playing, now on your phone — single player or with friends online.
```

---

## Description (4000 chars max)
```
Trump brings the classic 4-player trick-taking card game to your pocket — clean, fast, and exactly the way you remember it from home games on a Sunday afternoon.

Partner up across the table and race your opponents to seven books. Play a smart lead, read the trump, and squeeze every trick out of your hand.

FEATURES

• Single player vs three AI opponents — no account, no signup, just tap and play
• Online multiplayer with real-time crossplay between iOS and Android
• Create a private room and share a 6-character code to invite friends
• Empty seats automatically filled with AI so you never have to wait
• Strict rule enforcement: follow suit, trump wins, highest card takes the trick
• Cards that can't legally be played are dimmed — no accidental misplays
• Session win tracking so you can settle who's the real champion
• 60-second turn timer in multiplayer keeps the game moving
• Seamless disconnect and rejoin: AI covers your seat, you take control back on your next turn
• Portrait layout optimized for one-handed play
• No ads. No in-app purchases. No tracking.

HOW IT WORKS

Four players sit at the table — you at the bottom, your partner across from you, opponents on either side. The losing team deals the next round; the winning team gets to choose trump. Whoever is seated to the left of the dealer picks the trump suit from their first five cards, then leads the very first trick.

Trump beats every non-trump card. Higher trump beats lower trump. You must follow the suit that was led if you have a card of it — otherwise, anything goes, including dropping trump. Win seven tricks before the opponents do and the round is yours.

MULTIPLAYER

Tap Multiplayer, pick a guest name, and create or join a room with a 6-character code. Your username is session-only — we don't store it, there's no account, and there's nothing to sign up for. Room codes are easy to share by text, voice, or whatever app you already use. AI fills any empty seat, so you can play with one friend, two, or three — always four at the table.

FAIR PLAY

The game server is authoritative in multiplayer — every card played, every trump selected, and every trick resolved is checked against the rules. Cheating is not possible. If a player disconnects or runs out of time, AI takes over for them without interrupting the game.

PRIVACY

Trump collects no personal information. No ads. No trackers. No analytics SDKs. Your gameplay is yours.

Bring friends. Pick a partner. Call a suit. See who can get to seven first.
```

---

## Keywords (100 chars max, comma-separated — no spaces after commas to save room)
```
trump,card game,trick taking,4 player,spades,whist,euchre,partner,multiplayer,online cards,strategy
```

Character count: ~96

---

## Support URL
```
https://YOUR-GITHUB-USERNAME.github.io/trump-card-game/support.html
```
(Replace with your actual hosted URL — see `marketing/README.md` for hosting instructions.)

---

## Marketing URL (optional)
```
https://YOUR-GITHUB-USERNAME.github.io/trump-card-game/
```

---

## Privacy Policy URL (required)
```
https://YOUR-GITHUB-USERNAME.github.io/trump-card-game/privacy-policy.html
```

---

## Copyright
```
© 2026 Randy Ramsaywack
```

---

## Age Rating Questionnaire (expected answers → 4+)

| Question | Answer |
|---|---|
| Cartoon or Fantasy Violence | None |
| Realistic Violence | None |
| Sexual Content or Nudity | None |
| Profanity or Crude Humor | None |
| Alcohol, Tobacco, or Drug Use or References | None |
| Mature/Suggestive Themes | None |
| Horror/Fear Themes | None |
| Medical/Treatment Information | None |
| Prolonged Graphic or Sadistic Realistic Violence | None |
| Gambling and Contests | No |
| Simulated Gambling | None |
| Unrestricted Web Access | No |
| **Resulting rating** | **4+** |

---

## App Privacy (Data Collection Questionnaire)

Answer: **No, we do not collect data from this app.**

Rationale:
- No analytics SDK
- No ads SDK
- Multiplayer username is session-only and discarded when the room closes
- Server holds IP only transiently for the life of the network connection (standard IP use, not "data collection" in Apple's sense)
- No crash reporting that sends data to third parties
- No Apple ID, Game Center, or social login

If Apple flags this, switch to "Yes, we collect data" and declare:
- **Diagnostics** → Crash Data → Not linked to you → Not used for tracking → App Functionality
- **Identifiers** → User ID → Not linked to you → Not used for tracking → App Functionality (this covers the guest username)

---

## TestFlight — Test Information

### Beta App Description
```
Trump is a 4-player trick-taking card game. Play single-player against three AI opponents, or join online multiplayer rooms and play with friends across iOS and Android. Teams of two race to win seven tricks (books) per round. First team to seven wins.
```

### Beta App Feedback Email
```
randyramsaywack@gmail.com
```

### What to Test (per build, shown in TestFlight app)
```
First public TestFlight build of Trump.

Please try:
• Single-player mode vs 3 AI opponents — finish a full round (7 books)
• Multiplayer: create a room, share the 6-character code with a friend, play a full round together
• Rules enforcement: try to play cards that should be invalid (they should be dimmed and unselectable)
• Trump selection UI when you're the player to the left of the dealer
• Rotating dealers after each round

Report any crashes, UI glitches, cards that shouldn't be playable but are, or turns that feel stuck.
```

### License Agreement
Standard Apple EULA — leave default.

---

## App Review Information (shown only to Apple reviewers)

### Contact
| Field | Value |
|---|---|
| First Name | Randy |
| Last Name | Ramsaywack |
| Phone | _your phone_ |
| Email | randyramsaywack@gmail.com |

### Demo Account
**Not required.** Leave blank and check "Sign-in not required."

### Notes (for Beta App Review and full App Review)
```
Trump is a classic 4-player trick-taking card game.

HOW TO LAUNCH
1. Open the app.
2. Tap "Single Player" to play immediately against 3 AI opponents — no sign-in required.

MULTIPLAYER
1. From the main menu, tap "Multiplayer".
2. Enter any temporary guest username (no account, no email, nothing stored).
3. Tap "Create Room" to generate a 6-character code, or "Join Room" to enter an existing code.
4. The room creator can start the game with 2, 3, or 4 real players — any empty seats are filled automatically by AI.

GAME RULES (for reference while reviewing)
• 4 players, 2 teams of 2, standard 52-card deck.
• One player (to the left of the dealer) picks a trump suit each round.
• Players must follow the suit that was led if they have it.
• Highest trump wins the trick; if no trump was played, highest card of the led suit wins.
• First team to win 7 tricks ("books") wins the round.

PRIVACY AND DATA
• No account, login, or registration at any point.
• Username used in multiplayer is a temporary in-session label only.
• No analytics SDKs, no ads, no tracking, no in-app purchases.
• See privacy policy at the URL provided in App Information.

GAMBLING
This is not a gambling app. There is no real-money or virtual-currency wagering, no casino mechanics, no slot/dice randomness beyond the deal of a standard 52-card deck, and no purchases of any kind.

TESTING SHORTCUT
To see multiplayer in action without a second device, create a room on device A and join it on device B using the 6-character code shown on device A's screen. Or simply use Single Player mode — the full game loop (deal, trump selection, 13-trick round, win screen) is testable offline with AI opponents.
```

---

## Export Compliance

The app does NOT use non-exempt encryption. Already set in `Trump/Trump-Info.plist`:
```
<key>ITSAppUsesNonExemptEncryption</key>
<false />
```
This means no export compliance documentation is needed and TestFlight will not prompt.

---

## Version / Build Numbers

Current:
- `MARKETING_VERSION` (version) = **1.0.0**
- `CURRENT_PROJECT_VERSION` (build) is auto-incremented during the App Store build script.

For each new TestFlight upload, run:

```bash
export ASC_KEY_ID="YOUR_KEY_ID"
export ASC_ISSUER_ID="YOUR_ISSUER_ID"
export ASC_PRIVATE_KEY_PATH="$HOME/AuthKey_YOUR_KEY_ID.p8"
scripts/ios_build/build_appstore_ipa.sh
```

The script reads the latest uploaded build for the current `MARKETING_VERSION` from App Store Connect and sets `CURRENT_PROJECT_VERSION` to the next build. Only bump `MARKETING_VERSION` when you ship a new user-facing version.
