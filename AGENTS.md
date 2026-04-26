# AGENTS.md — Trump (Card Game)

## Project Overview

A mobile card game for iOS and Android built in Godot 4.x using GDScript.
4-player card game named "Trump". 2 teams of 2.
Supports single player vs AI and online multiplayer (up to 4 real players).

---

## Tech Stack

- **Engine:** Godot 4.x
- **Language:** GDScript
- **Target Platforms:** iOS and Android (crossplay supported)
- **Assets:** Placeholder assets only (to be replaced later)
- **Networking:** Godot built-in networking (ENet/WebSocket via MultiplayerAPI)
- **Server:** Dedicated server hosted on Oracle Cloud Free Tier (Always Free VM)
- **Domain:** Public domain to be configured later — architecture must support it

---

## Game Modes

### Single Player

- Human player vs 3 AI opponents
- No username required — human is displayed as "You"
- AI opponents have default names (e.g., "West", "North", "East")
- No network connection required

### Multiplayer

- Online, real-time, cross-platform (iOS + Android)
- 2–4 real players, empty seats filled with AI
- Guest username required before entering multiplayer (no account/login system)
- Username is temporary for the session only

---

## Game Rules (Source of Truth)

### Players & Teams

- 4 players total
- Teams: Player (human) + Partner (across) vs Left Opponent + Right Opponent
- Table layout: Human = Bottom, Partner = Top, Left Opponent = Left, Right Opponent = Right
- Teams are fixed for the session

### Deck

- Standard 52-card deck
- Ranks high to low: A, K, Q, J, 10, 9, 8, 7, 6, 5, 4, 3, 2
- 4 suits: Spades, Hearts, Diamonds, Clubs

### Dealer & Round Rotation

- The LOSING team deals the next round
- The WINNING team gets trump selection in the next round
- First round dealer is randomly determined at session/game start
- The trump selector is always the player to the LEFT of the dealer
- This means the trump selector is always on the winning team
- Dealer rotates within the dealing team each round (if same team loses consecutive
rounds, the other member of that team deals next)

### Dealing

- The losing team's current dealer deals the cards
- The first 5 cards are dealt ONLY to the player to the LEFT of the dealer (trump selector)
- The trump selector MUST choose one of the 4 suits as trump — no passing
- After trump is declared, dealing continues clockwise until all 4 players have 13 cards
- The trump selector keeps their initial 5 cards as part of their 13-card hand
- All 4 players end up with exactly 13 cards

### Trump

- Trump suit chosen by trump selector before full dealing completes
- Trump can be led at any time (does NOT need to be broken first)
- Trump beats all non-trump cards
- Higher trump beats lower trump

### Turn Order & Leading

- The trump selector always leads the very first trick of the round
- The winner of each trick leads the next trick
- Play proceeds clockwise

### Following Suit Rules

- Players MUST follow the led suit if they have a card of that suit
- If a player cannot follow suit, they may play trump OR any other card
- There is no restriction on when trump can be played or led
- Invalid cards are visually dimmed and cannot be selected or played
- Only valid playable cards are highlighted and selectable on a player's turn

### Trick Resolution

- If trump cards are played: highest trump wins the trick
- If no trump cards are played: highest card of the led suit wins the trick
- Off-suit non-trump cards never win a trick
- The individual player who wins the trick leads the next trick

### Books (Tricks)

- A "book" is a won trick
- Running book count tracked and displayed for both teams throughout the round

### Winning a Round

- First team to 7 books wins the round
- Game ends immediately when a team reaches 7 books
- No book carry-over between rounds — full reset each round
- Winning team gets trump selection next round
- Losing team deals next round

---

## Turn Timer (Multiplayer Only)

- Each player has 60 seconds to play a card on their turn
- Timer is visible to ALL players in the game
- If the timer expires:
  - AI automatically selects and plays a valid card for that player
  - AI continues to play for that player on subsequent turns until the player
  interacts with the game (taps a card or otherwise inputs an action)
  - Once the player interacts, they immediately regain control on their next turn
- Timer does not apply in single player mode

---

## Session Tracking

- Track wins per team across all rounds in the current session
- Session stats reset only when the app is closed or a new session is explicitly started
- Display format: "Your Team: X wins | Opponents: Y wins"
- Shown on win screen and persistently visible during play

---

## Multiplayer — Network Architecture

### Stack

- Godot MultiplayerAPI (ENet for UDP, WebSocket fallback for mobile)
- Dedicated server on Oracle Cloud Free Tier (Always Free VM)
- Godot headless server export running as a systemd service on the VM
- Public domain to be configured — code must use a configurable server address
(not hardcoded IP)

### Server Responsibilities

- Host all game rooms
- Manage room state (waiting, in-game, closed)
- Relay all game actions between players
- Handle AI logic for disconnected/timed-out players server-side
- Assign new host if current host disconnects

### Room System

- Room codes: 6 characters, uppercase letters only, excludes I/O for readability (e.g., `ABFKMR`)
- Players can CREATE a room (become host) or JOIN a room via code
- Room creator (host) can start the game with 2, 3, or 4 players — empty seats filled with AI
- Room persists if host disconnects:
  - Server promotes another connected player to host
  - If no connected players remain, room closes after a short grace period
- Disconnected players can rejoin their room using the same room code
while the room is still active
- On rejoin, AI releases control back to the returning player on their next turn

### Player Disconnect Behavior

- On disconnect: AI immediately takes over that player's seat
- Seat is held for the player to rejoin using the room code
- On rejoin: player regains control on their next turn
- If room host disconnects: another player is prompted to accept host role
- If no one accepts within a timeout period: room closes

### Game Authority

- Server is authoritative for all game state
- Clients send intended actions (play card, select trump) to server
- Server validates actions against game rules before applying
- Server broadcasts state updates to all clients
- Clients are display/input only — no client-side rule enforcement for multiplayer

---

## Self-Verification via Screenshots (Codex)

### Purpose

Codex must use screenshots to visually verify its own work at every major
milestone. Do not assume code is working — prove it visually before moving on.

### When to Take Screenshots

- After any new scene or UI element is added
- After implementing each game state transition
- After dealing logic is implemented (verify card counts, layout)
- After trump selection UI is built
- After each AI behavior is added
- After trick resolution is implemented
- After win screen is built
- After any bug fix — screenshot before AND after to confirm resolution
- Any time behavior is unexpected or uncertain

### What to Verify in Screenshots

- **Layout:** Cards positioned correctly at all 4 player positions
- **Card counts:** All players have correct number of cards at each stage
- **State transitions:** Correct UI shown for each game state
- **Trump selection:** 5 cards visible, suit buttons present and functional
- **Valid card highlighting:** Correct cards highlighted/dimmed on human's turn
- **Book counter:** Incrementing correctly for the right team
- **Turn indicator:** Pointing to the correct active player
- **Win screen:** Triggered at exactly 7 books, shows correct winner
- **Timer UI:** Visible to all players, counts down correctly (multiplayer)

### Screenshot Debug Workflow

1. Implement a feature or fix
2. Run the scene in Godot editor
3. Take a screenshot using MCP screenshot tool
4. Analyze the screenshot for correctness against AGENTS.md rules
5. If something looks wrong — fix it, screenshot again to confirm
6. Only move to the next feature when the screenshot confirms correct behavior
7. If a bug cannot be identified from the screenshot alone, add debug labels
  temporarily to the scene to expose state, screenshot again, then remove labels

### What Counts as "Verified"

- The visual output matches the expected behavior described in AGENTS.md
- No placeholder positions are misaligned
- No cards are missing or duplicated
- Game state transitions happen at the correct time
- If uncertain whether something is correct — ask Randy before proceeding

---

## Project Structure

```
project/
├── AGENTS.md
├── project.godot
├── scenes/
│   ├── main_menu.tscn
│   ├── mode_select.tscn
│   ├── multiplayer_lobby.tscn
│   ├── room_waiting.tscn
│   ├── game_table.tscn
│   ├── card.tscn
│   └── ui/
│       ├── score_display.tscn
│       ├── trump_selector.tscn
│       ├── win_screen.tscn
│       └── turn_timer.tscn
├── scripts/
│   ├── game_manager.gd
│   ├── deck.gd
│   ├── card.gd
│   ├── hand.gd
│   ├── trick.gd
│   ├── ai_player.gd
│   ├── player.gd
│   ├── round_manager.gd
│   ├── network_manager.gd
│   ├── server_game_manager.gd
│   └── ui/
│       ├── game_table_ui.gd
│       ├── trump_selector_ui.gd
│       ├── win_screen_ui.gd
│       └── turn_timer_ui.gd
├── server/
│   ├── main_server.gd
│   └── room_manager.gd
├── assets/
│   ├── cards/
│   ├── ui/
│   ├── sounds/
│   └── fonts/
└── autoloads/
    ├── game_state.gd
    └── network_state.gd
```

---

## Game State Machine

```
IDLE
  → MODE_SELECT (single player or multiplayer)

[SINGLE PLAYER PATH]
  → SESSION_START (randomize first dealer)
  → DEALING_INITIAL (deal 5 cards to trump selector)
  → TRUMP_SELECTION (trump selector chooses suit)
  → DEALING_REMAINING (deal remaining cards, 13 each)
  → PLAYER_TURN (human input or AI — trump selector leads first)
  → TRICK_RESOLUTION (determine winner, award book)
  → CHECK_WIN (either team at 7 books?)
      → YES → ROUND_OVER
      → NO  → PLAYER_TURN (trick winner leads)
  → ROUND_OVER (animation, update session wins)
  → NEXT_ROUND_SETUP (rotate dealer, assign trump selector)
  → IDLE

[MULTIPLAYER PATH]
  → MULTIPLAYER_MENU (enter username)
  → ROOM_CREATE or ROOM_JOIN (6-char code)
  → ROOM_WAITING (host sees player list, can start with 2–4 humans)
  → SESSION_START (server randomizes dealer, notifies all clients)
  → DEALING_INITIAL (server deals 5 to trump selector, sends to that client)
  → TRUMP_SELECTION (trump selector client sends choice to server)
  → DEALING_REMAINING (server deals remaining, sends hands to each client)
  → PLAYER_TURN (active player client sends action, server validates + broadcasts)
  → TRICK_RESOLUTION (server resolves, broadcasts result)
  → CHECK_WIN
      → YES → ROUND_OVER (server triggers, all clients show result)
      → NO  → PLAYER_TURN
  → ROUND_OVER (all clients show animation + session wins)
  → NEXT_ROUND_SETUP (server manages rotation)
  → IDLE
```

---

## AI Behavior Guidelines

- AI must follow all game rules (suit following, trump rules)
- Basic AI strategy:
  - Follow suit with lowest winning card if possible
  - Play trump if cannot follow suit and trick is losable
  - Discard lowest off-suit card if trick is already won by partner
  - Trump selector AI: pick the suit with the most cards in hand
- AI delay: 0.5–1.0 seconds before acting (feels natural)
- In multiplayer, AI runs server-side only
- In single player, AI runs client-side
- AI takeover in multiplayer is seamless — no visible mode change to other players

---

## UI/UX Requirements

### Main Menu

- Game title: "Trump"
- Buttons: "Single Player" and "Multiplayer"

### Multiplayer Lobby

- Username entry field (guest, session only)
- "Create Room" button → generates 6-char code, shows waiting room
- "Join Room" button → text field for code entry

### Waiting Room

- Shows room code prominently (for sharing)
- Lists connected players and AI placeholders for empty seats
- Host sees "Start Game" button (active with 2+ players)
- Non-host players see "Waiting for host..."
- Shows when players join/leave

### Table Layout

- Portrait mode only
- Human hand at bottom (face-up, playable)
- Partner hand at top (face-down)
- Left opponent hand on left (face-down)
- Right opponent hand on right (face-down)
- In multiplayer: player usernames shown at each seat
- Center area for active trick (4 card slots)
- Trump suit icon/label shown prominently

### HUD (always visible during play)

- Current trump suit
- Round books: "Your Team: X | Opponents: Y"
- Session wins: "Session — You: X | Opponents: Y"
- Active player indicator
- Turn timer (multiplayer only): countdown shown for all players,
highlights urgently when under 10 seconds

### Trump Selection UI

- Show trump selector's first 5 cards
- 4 suit buttons: Spades, Hearts, Diamonds, Clubs
- Human trump selector: wait for input
- AI trump selector: auto-select after short delay, show result briefly

### Card Interaction

- Valid cards: highlighted, fully opaque, tappable
- Invalid cards: dimmed, not selectable (enforced — cannot be played)
- Tap to select (highlight), tap again or tap "Play" to confirm
- Minimum touch target: 48x48dp

### Win Screen

- Triggered when a team hits 7 books
- Win animation (human team wins) or loss animation (opponents win)
- "Your Team Wins!" or "Opponents Win!"
- Updated session wins displayed
- Buttons: "Next Round" and "Main Menu"
- In multiplayer: all players see the same win screen simultaneously

### Sound Effects

- Card shuffle during dealing
- Card play when any card hits the table
- Trick win sound when a book is claimed
- Win fanfare on round win
- Loss sound on round loss

---

## Platform Notes

- Portrait mode only
- Touch input — no mouse/keyboard assumptions
- Crossplay: iOS and Android in the same multiplayer game
- Test on small (iPhone SE) and large (iPad / large Android) screens
- Server: Oracle Cloud Free Tier VM, Godot headless server binary
- Server address must be configurable (not hardcoded) for domain setup later

---

## Development Priorities (in order)

1. Core game logic (deck, dealing, trump selection, trick resolution)
2. Game state machine
3. Basic UI (table layout, card display, playable human hand)
4. Single player AI
5. Trump selection flow (human and AI paths)
6. Win condition + round reset + dealer rotation
7. Session win tracking + win screen animation
8. Sound effects
9. Multiplayer networking (server setup, room system, state sync)
10. Turn timer + AI takeover on timeout
11. Disconnect/rejoin handling
12. Host migration
13. Mobile optimization and touch input polish

---

## Important Rules Reminders for Agent

- **Never assume a rule — refer to this document first, ask Randy if unclear**
- Trump selector is ALWAYS the player to the LEFT of the dealer
- Losing team deals — winning team always gets trump selection
- Trump selector leads the first trick every round
- Trick winner leads the next trick
- Trump does NOT need to be broken
- 7 books = immediate win, round ends on the spot
- Trump selector keeps first 5 cards — all players end with exactly 13
- Dealer rotates between the two members of the losing/dealing team
- Session wins persist for the session — books and round results do not carry over
- Multiplayer: server is authoritative, clients are display/input only
- Invalid cards cannot be played — enforced both client-side (UI) and server-side
- AI takes over on disconnect or turn timer expiry — player reclaims on next interaction
- Room persists on host disconnect — another player is promoted to host
- Take a screenshot to verify work at every major milestone — do not assume it works

```

```

