# Trump Card Game — Single Player Bootstrap Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bootstrap a playable single-player Trump card game in Godot 4.6.2 with core game logic, basic UI, and AI opponents — no multiplayer.

**Architecture:** Pure GDScript with a singleton GameManager autoload driving a state machine. Scenes handle display only; all game rules live in scripts. The human player is always seat 0 (bottom), partner is seat 1 (top), opponents are seats 2 (left) and 3 (right). Teams: 0+1 vs 2+3.

**Tech Stack:** Godot 4.6.2, GDScript, Android/iOS portrait mode, Godot MCP for scene creation and run verification, Write tool for .gd scripts.

---

## Pre-Flight: Configure GODOT_PATH for MCP

The Godot MCP must find the Godot executable. Before any task, set `GODOT_PATH` to the installed binary.

- [ ] **Confirm Godot binary path**

  Godot 4.6.2 is at: `C:\Users\randy\OneDrive\Desktop\Godot_v4.6.2-stable_win64.exe`

- [ ] **Set GODOT_PATH in the project's .mcp.json**

  Create `C:\Users\randy\Documents\Code\trump-card-game\.mcp.json`:

  ```json
  {
    "mcpServers": {
      "godot": {
        "command": "npx",
        "args": ["-y", "@coding-solo/godot-mcp"],
        "env": {
          "GODOT_PATH": "C:\\Users\\randy\\OneDrive\\Desktop\\Godot_v4.6.2-stable_win64.exe"
        }
      }
    }
  }
  ```

- [ ] **Reload MCP and verify Godot version resolves**

  Use `mcp__godot__get_godot_version`. Expected: version string containing "4.6".

---

## File Map

| File | Responsibility |
|------|---------------|
| `project.godot` | Engine config, autoloads, display settings |
| `scripts/card.gd` | Card data: Suit enum, Rank enum, value comparison |
| `scripts/deck.gd` | 52-card deck creation, shuffle, deal |
| `scripts/hand.gd` | Card collection, follow-suit enforcement, valid card filtering |
| `scripts/trick.gd` | One trick: 4 cards, led suit tracking, winner resolution |
| `scripts/player.gd` | Base player: seat index, team assignment |
| `scripts/ai_player.gd` | AI strategy: suit selection, card selection logic |
| `scripts/round_manager.gd` | One round: dealing sequence, trick loop, book tracking, win detection |
| `autoloads/game_state.gd` | Session singleton: session wins, dealer rotation, round sequencing |
| `scenes/card.tscn` | Visual card: face/back display, highlight/dim state |
| `scenes/game_table.tscn` | Main game: 4 player positions, center trick area, HUD |
| `scripts/ui/game_table_ui.gd` | Wires game_state signals to game_table scene nodes |
| `scenes/ui/trump_selector.tscn` | Trump selection overlay: 5 cards + 4 suit buttons |
| `scripts/ui/trump_selector_ui.gd` | Handles trump selector interaction and AI auto-select |
| `scenes/ui/win_screen.tscn` | Round result overlay: winner text, session wins, buttons |
| `scripts/ui/win_screen_ui.gd` | Wires win screen to game_state and handles navigation |

---

## Task 1: Project Setup

**Files:**
- Create: `project.godot`
- Create: all directories per CLAUDE.md project structure
- Create: `autoloads/game_state.gd` (stub)
- Create: `autoloads/network_state.gd` (stub — needed by project.godot autoload list)
- Create: `icon.svg` (minimal placeholder)

- [ ] **Step 1: Create directory structure**

  Run these Write calls (or use Bash mkdir) to create all directories:
  ```
  scripts/
  scripts/ui/
  scenes/
  scenes/ui/
  autoloads/
  assets/cards/
  assets/ui/
  assets/sounds/
  assets/fonts/
  ```

  ```bash
  mkdir -p "C:/Users/randy/Documents/Code/trump-card-game/scripts/ui"
  mkdir -p "C:/Users/randy/Documents/Code/trump-card-game/scenes/ui"
  mkdir -p "C:/Users/randy/Documents/Code/trump-card-game/autoloads"
  mkdir -p "C:/Users/randy/Documents/Code/trump-card-game/assets/cards"
  mkdir -p "C:/Users/randy/Documents/Code/trump-card-game/assets/ui"
  mkdir -p "C:/Users/randy/Documents/Code/trump-card-game/assets/sounds"
  mkdir -p "C:/Users/randy/Documents/Code/trump-card-game/assets/fonts"
  ```

- [ ] **Step 2: Create minimal icon.svg**

  Write `icon.svg`:
  ```xml
  <svg xmlns="http://www.w3.org/2000/svg" width="128" height="128">
    <rect width="128" height="128" fill="#2d6a4f"/>
    <text x="64" y="80" font-size="64" text-anchor="middle" fill="white">♠</text>
  </svg>
  ```

- [ ] **Step 3: Create autoload stubs**

  Write `autoloads/game_state.gd`:
  ```gdscript
  extends Node
  # GameState autoload — session-level singleton
  # Full implementation in Task 7
  ```

  Write `autoloads/network_state.gd`:
  ```gdscript
  extends Node
  # NetworkState autoload — multiplayer only, stub for now
  ```

- [ ] **Step 4: Create project.godot**

  Write `project.godot`:
  ```ini
  ; Engine configuration file.
  ; Generated for Trump card game — Godot 4.6.2

  config_version=5

  [application]

  config/name="Trump"
  config/run/main_scene="res://scenes/game_table.tscn"
  config/features=PackedStringArray("4.6", "Mobile")
  config/icon="res://icon.svg"

  [autoload]

  GameState="*res://autoloads/game_state.gd"
  NetworkState="*res://autoloads/network_state.gd"

  [display]

  window/size/viewport_width=390
  window/size/viewport_height=844
  window/size/resizable=false
  window/handheld/orientation=1

  [rendering]

  renderer/rendering_method="mobile"
  renderer/rendering_method.mobile="gl_compatibility"
  ```

- [ ] **Step 5: Verify project loads**

  Use `mcp__godot__get_project_info` with `projectPath = "C:/Users/randy/Documents/Code/trump-card-game"`.
  Expected: project name "Trump" returned without errors.

---

## Task 2: card.gd — Card Data Model

**Files:**
- Create: `scripts/card.gd`

- [ ] **Step 1: Write card.gd**

  Write `scripts/card.gd`:
  ```gdscript
  class_name Card

  enum Suit { SPADES = 0, HEARTS = 1, DIAMONDS = 2, CLUBS = 3 }
  enum Rank { TWO = 2, THREE = 3, FOUR = 4, FIVE = 5, SIX = 6, SEVEN = 7,
              EIGHT = 8, NINE = 9, TEN = 10, JACK = 11, QUEEN = 12, KING = 13, ACE = 14 }

  const SUIT_SYMBOLS: Dictionary = {
      Suit.SPADES: "♠",
      Suit.HEARTS: "♥",
      Suit.DIAMONDS: "♦",
      Suit.CLUBS: "♣"
  }

  const SUIT_NAMES: Dictionary = {
      Suit.SPADES: "Spades",
      Suit.HEARTS: "Hearts",
      Suit.DIAMONDS: "Diamonds",
      Suit.CLUBS: "Clubs"
  }

  const RANK_NAMES: Dictionary = {
      Rank.TWO: "2", Rank.THREE: "3", Rank.FOUR: "4", Rank.FIVE: "5",
      Rank.SIX: "6", Rank.SEVEN: "7", Rank.EIGHT: "8", Rank.NINE: "9",
      Rank.TEN: "10", Rank.JACK: "J", Rank.QUEEN: "Q", Rank.KING: "K", Rank.ACE: "A"
  }

  var suit: Suit
  var rank: Rank

  func _init(s: Suit, r: Rank) -> void:
      suit = s
      rank = r

  ## Returns true if this card beats `other` given the led suit and trump suit.
  ## Caller must pass the led_suit of the current trick.
  func beats(other: Card, led_suit: Suit, trump_suit: Suit) -> bool:
      var self_is_trump := suit == trump_suit
      var other_is_trump := other.suit == trump_suit
      # Trump always beats non-trump
      if self_is_trump and not other_is_trump:
          return true
      if other_is_trump and not self_is_trump:
          return false
      # Both trump — higher rank wins
      if self_is_trump and other_is_trump:
          return rank > other.rank
      # Neither is trump — only led suit can win
      var self_is_led := suit == led_suit
      var other_is_led := other.suit == led_suit
      if self_is_led and not other_is_led:
          return true
      if other_is_led and not self_is_led:
          return false
      # Both led suit — higher rank wins
      if self_is_led and other_is_led:
          return rank > other.rank
      # Neither is trump nor led suit — neither wins
      return false

  func display_name() -> String:
      return RANK_NAMES[rank] + SUIT_SYMBOLS[suit]

  func suit_name() -> String:
      return SUIT_NAMES[suit]
  ```

- [ ] **Step 2: Verify card.gd parses — run project once**

  Use `mcp__godot__run_project` with `projectPath = "C:/Users/randy/Documents/Code/trump-card-game"`.
  Then `mcp__godot__get_debug_output`. Expected: no parse errors for card.gd.
  (The run will fail with "no main scene" if game_table.tscn doesn't exist yet — that's OK, only check for script parse errors.)

---

## Task 3: deck.gd — Deck Management

**Files:**
- Create: `scripts/deck.gd`

- [ ] **Step 1: Write deck.gd**

  Write `scripts/deck.gd`:
  ```gdscript
  class_name Deck

  var cards: Array[Card] = []

  func _init() -> void:
      _build()

  func _build() -> void:
      cards.clear()
      for s in Card.Suit.values():
          for r in Card.Rank.values():
              cards.append(Card.new(s as Card.Suit, r as Card.Rank))
      # Sanity: 4 suits * 13 ranks = 52 cards
      assert(cards.size() == 52, "Deck must have 52 cards, got %d" % cards.size())

  func shuffle() -> void:
      cards.shuffle()

  ## Deal `count` cards off the top (end of array = top).
  ## Returns array of dealt cards. Modifies deck in place.
  func deal(count: int) -> Array[Card]:
      count = min(count, cards.size())
      var dealt: Array[Card] = []
      for _i in range(count):
          dealt.append(cards.pop_back())
      return dealt

  func remaining() -> int:
      return cards.size()
  ```

- [ ] **Step 2: Run project and check debug output for errors**

  Use `mcp__godot__run_project` + `mcp__godot__get_debug_output`.
  Expected: no parse errors for deck.gd.

---

## Task 4: hand.gd — Hand Management and Follow-Suit Enforcement

**Files:**
- Create: `scripts/hand.gd`

- [ ] **Step 1: Write hand.gd**

  Write `scripts/hand.gd`:
  ```gdscript
  class_name Hand

  var cards: Array[Card] = []

  func add_cards(new_cards: Array[Card]) -> void:
      cards.append_array(new_cards)

  func remove_card(card: Card) -> bool:
      var idx := cards.find(card)
      if idx >= 0:
          cards.remove_at(idx)
          return true
      return false

  ## Returns the subset of cards the player is allowed to play.
  ## `led_suit`: the suit of the first card played in this trick.
  ##             Pass -1 if this player is leading (all cards valid).
  ## `trump_suit`: the current trump suit (for reference, but no trump restriction).
  func get_valid_cards(led_suit: int, _trump_suit: Card.Suit) -> Array[Card]:
      # Leading — all cards valid
      if led_suit == -1:
          return cards.duplicate()
      var led := led_suit as Card.Suit
      # Must follow led suit if possible
      var suit_cards: Array[Card] = cards.filter(func(c: Card) -> bool: return c.suit == led)
      if not suit_cards.is_empty():
          return suit_cards
      # Cannot follow suit — any card is valid
      return cards.duplicate()

  func has_suit(suit: Card.Suit) -> bool:
      return cards.any(func(c: Card) -> bool: return c.suit == suit)

  func size() -> int:
      return cards.size()

  func is_empty() -> bool:
      return cards.is_empty()

  ## For AI: returns all cards of a given suit
  func cards_of_suit(suit: Card.Suit) -> Array[Card]:
      return cards.filter(func(c: Card) -> bool: return c.suit == suit)

  ## For AI: returns lowest card by rank
  func lowest_card(from: Array[Card]) -> Card:
      if from.is_empty():
          return null
      var lowest: Card = from[0]
      for c in from.slice(1):
          if c.rank < lowest.rank:
              lowest = c
      return lowest

  ## For AI: returns highest card by rank
  func highest_card(from: Array[Card]) -> Card:
      if from.is_empty():
          return null
      var highest: Card = from[0]
      for c in from.slice(1):
          if c.rank > highest.rank:
              highest = c
      return highest

  ## For AI: suit with most cards in hand
  func dominant_suit() -> Card.Suit:
      var counts: Dictionary = {}
      for s in Card.Suit.values():
          counts[s] = cards_of_suit(s as Card.Suit).size()
      var best_suit: Card.Suit = Card.Suit.SPADES
      var best_count := 0
      for s in counts:
          if counts[s] > best_count:
              best_count = counts[s]
              best_suit = s as Card.Suit
      return best_suit
  ```

- [ ] **Step 2: Run project and check debug output for errors**

  Use `mcp__godot__run_project` + `mcp__godot__get_debug_output`.
  Expected: no parse errors for hand.gd.

---

## Task 5: trick.gd — Trick Resolution

**Files:**
- Create: `scripts/trick.gd`

- [ ] **Step 1: Write trick.gd**

  Write `scripts/trick.gd`:
  ```gdscript
  class_name Trick

  ## Each entry: { "player_index": int, "card": Card }
  var played: Array[Dictionary] = []
  var led_suit: int = -1  # -1 until first card played; cast to Card.Suit after
  var trump_suit: Card.Suit

  func _init(trump: Card.Suit) -> void:
      trump_suit = trump

  func play_card(player_index: int, card: Card) -> void:
      assert(played.size() < 4, "Trick is already complete")
      if played.is_empty():
          led_suit = card.suit
      played.append({"player_index": player_index, "card": card})

  func is_complete() -> bool:
      return played.size() == 4

  ## Returns the player_index of the trick winner.
  ## Must only be called when is_complete() is true.
  func get_winner_index() -> int:
      assert(is_complete(), "Cannot get winner of incomplete trick")
      var winning := played[0]
      for entry in played.slice(1):
          var challenger: Card = entry.card
          var current_winner: Card = winning.card
          if challenger.beats(current_winner, led_suit as Card.Suit, trump_suit):
              winning = entry
      return winning.player_index

  ## Returns the winning card (for UI display)
  func get_winning_card() -> Card:
      assert(is_complete(), "Cannot get winning card of incomplete trick")
      return played[get_winner_index() - played[0].player_index].card if false else _find_winning_card()

  func _find_winning_card() -> Card:
      var winning := played[0]
      for entry in played.slice(1):
          if (entry.card as Card).beats(winning.card as Card, led_suit as Card.Suit, trump_suit):
              winning = entry
      return winning.card

  func cards_played() -> int:
      return played.size()

  func get_card_for_player(player_index: int) -> Card:
      for entry in played:
          if entry.player_index == player_index:
              return entry.card
      return null
  ```

- [ ] **Step 2: Run project and check debug output for errors**

  Use `mcp__godot__run_project` + `mcp__godot__get_debug_output`.
  Expected: no parse errors for trick.gd.

---

## Task 6: player.gd + ai_player.gd

**Files:**
- Create: `scripts/player.gd`
- Create: `scripts/ai_player.gd`

- [ ] **Step 1: Write player.gd**

  Write `scripts/player.gd`:
  ```gdscript
  class_name Player

  ## Seat indices: 0=bottom(human), 1=top(partner), 2=left, 3=right
  ## Teams: 0+1 = team 0, 2+3 = team 1
  var seat_index: int
  var display_name: String
  var hand: Hand
  var is_human: bool

  func _init(idx: int, name: String, human: bool) -> void:
      seat_index = idx
      display_name = name
      hand = Hand.new()
      is_human = human

  func team() -> int:
      return 0 if seat_index in [0, 1] else 1

  func clear_hand() -> void:
      hand = Hand.new()
  ```

- [ ] **Step 2: Write ai_player.gd**

  Write `scripts/ai_player.gd`:
  ```gdscript
  class_name AIPlayer
  extends Player

  func _init(idx: int, name: String) -> void:
      super._init(idx, name, false)

  ## Choose trump suit: pick the suit with most cards in hand.
  func choose_trump() -> Card.Suit:
      return hand.dominant_suit()

  ## Choose which card to play given the current trick state.
  ## `valid_cards`: cards the AI is allowed to play (already filtered by follow-suit rules)
  ## `current_trick`: the Trick in progress (may have 0-3 cards already played)
  ## `partner_seat`: seat index of this AI's partner
  func choose_card(valid_cards: Array[Card], current_trick: Trick, partner_seat: int) -> Card:
      if valid_cards.size() == 1:
          return valid_cards[0]

      var trump := current_trick.trump_suit
      var led := current_trick.led_suit

      # Case 1: Leading the trick — play lowest card (conservative)
      if current_trick.cards_played() == 0:
          return hand.lowest_card(valid_cards)

      # Determine current winner of trick
      var current_winner_idx := current_trick.get_winner_index() if current_trick.cards_played() > 0 else -1
      var partner_is_winning := (current_winner_idx == partner_seat)

      # Case 2: Partner is currently winning — discard lowest off-suit card
      if partner_is_winning:
          var non_trump := valid_cards.filter(func(c: Card) -> bool: return c.suit != trump)
          if not non_trump.is_empty():
              return hand.lowest_card(non_trump)
          return hand.lowest_card(valid_cards)

      # Case 3: Try to win with lowest winning card
      var winning_card := _find_lowest_winner(valid_cards, current_trick)
      if winning_card != null:
          return winning_card

      # Case 4: Can't win — play trump if possible (and not already trump led)
      if led != trump:
          var trump_cards := valid_cards.filter(func(c: Card) -> bool: return c.suit == trump)
          if not trump_cards.is_empty():
              return hand.lowest_card(trump_cards)

      # Case 5: Can't win, can't trump — discard lowest
      return hand.lowest_card(valid_cards)

  ## Finds the lowest-ranked card in `valid_cards` that beats the current trick winner.
  ## Returns null if no card can win.
  func _find_lowest_winner(valid_cards: Array[Card], trick: Trick) -> Card:
      if trick.cards_played() == 0:
          return null
      # Find current winning card
      var winning_card: Card = null
      var winning_entry = null
      for entry in trick.played:
          if winning_entry == null:
              winning_entry = entry
          elif (entry.card as Card).beats(winning_entry.card as Card, trick.led_suit as Card.Suit, trick.trump_suit):
              winning_entry = entry
      if winning_entry == null:
          return null
      winning_card = winning_entry.card as Card

      var winners: Array[Card] = valid_cards.filter(
          func(c: Card) -> bool: return c.beats(winning_card, trick.led_suit as Card.Suit, trick.trump_suit)
      )
      if winners.is_empty():
          return null
      return hand.lowest_card(winners)
  ```

- [ ] **Step 3: Run project and check debug output for errors**

  Use `mcp__godot__run_project` + `mcp__godot__get_debug_output`.
  Expected: no parse errors.

---

## Task 7: round_manager.gd — One Round Orchestration

**Files:**
- Create: `scripts/round_manager.gd`

- [ ] **Step 1: Write round_manager.gd**

  Write `scripts/round_manager.gd`:
  ```gdscript
  class_name RoundManager

  signal state_changed(new_state: RoundState)
  signal hand_dealt(seat_index: int, cards: Array)
  signal trump_selection_needed(seat_index: int, initial_cards: Array)
  signal trump_declared(suit: Card.Suit)
  signal turn_started(seat_index: int, valid_cards: Array)
  signal card_played_signal(seat_index: int, card: Card)
  signal trick_completed(winner_seat: int, books: Array)
  signal round_ended(winning_team: int)

  enum RoundState {
      IDLE,
      DEALING_INITIAL,
      TRUMP_SELECTION,
      DEALING_REMAINING,
      PLAYER_TURN,
      TRICK_RESOLUTION,
      ROUND_OVER
  }

  var state: RoundState = RoundState.IDLE
  var players: Array[Player] = []
  var deck: Deck
  var trump_suit: Card.Suit
  var dealer_seat: int
  var trump_selector_seat: int
  var current_player_seat: int
  var current_trick: Trick
  var books: Array[int] = [0, 0]  # [team0, team1]
  var _ai_timer: float = 0.0
  var _ai_pending: bool = false

  const AI_DELAY_MIN := 0.5
  const AI_DELAY_MAX := 1.0
  const BOOKS_TO_WIN := 7

  func _init() -> void:
      pass

  ## Start a new round. `dealer` is the seat index of the dealer.
  ## `player_list` is Array[Player] with seats 0-3.
  func start_round(player_list: Array[Player], dealer: int) -> void:
      players = player_list
      dealer_seat = dealer
      trump_selector_seat = (dealer_seat + 1) % 4
      books = [0, 0]
      deck = Deck.new()
      deck.shuffle()
      for p in players:
          p.clear_hand()
      _set_state(RoundState.DEALING_INITIAL)

  func _set_state(new_state: RoundState) -> void:
      state = new_state
      state_changed.emit(new_state)
      _process_state()

  func _process_state() -> void:
      match state:
          RoundState.DEALING_INITIAL:
              _do_deal_initial()
          RoundState.TRUMP_SELECTION:
              _do_trump_selection()
          RoundState.DEALING_REMAINING:
              _do_deal_remaining()
          RoundState.PLAYER_TURN:
              _do_player_turn()

  func _do_deal_initial() -> void:
      # Deal 5 cards to trump selector only
      var initial := deck.deal(5)
      players[trump_selector_seat].hand.add_cards(initial)
      hand_dealt.emit(trump_selector_seat, initial)
      _set_state(RoundState.TRUMP_SELECTION)

  func _do_trump_selection() -> void:
      var selector := players[trump_selector_seat]
      trump_selection_needed.emit(trump_selector_seat, selector.hand.cards.duplicate())
      # If AI, schedule auto-selection
      if not selector.is_human:
          _schedule_ai_action()

  func ai_select_trump() -> void:
      var ai := players[trump_selector_seat] as AIPlayer
      var chosen := ai.choose_trump()
      declare_trump(chosen)

  ## Called by UI (human) or AI after trump selector picks a suit.
  func declare_trump(suit: Card.Suit) -> void:
      trump_suit = suit
      trump_declared.emit(suit)
      _set_state(RoundState.DEALING_REMAINING)

  func _do_deal_remaining() -> void:
      # Deal remaining 47 cards (5 already dealt) clockwise starting from trump selector
      # Each player needs 13 cards total; trump selector has 5, others have 0
      # Deal order: clockwise from trump selector
      # trump selector needs 8 more, others need 13
      var needs := [13, 13, 13, 13]
      needs[trump_selector_seat] = 8  # already has 5

      # Deal clockwise starting from trump selector
      var seat := trump_selector_seat
      while deck.remaining() > 0:
          if players[seat].hand.size() < needs[seat]:
              var deal_count := mini(needs[seat] - players[seat].hand.size(), deck.remaining())
              var new_cards := deck.deal(deal_count)
              players[seat].hand.add_cards(new_cards)
              hand_dealt.emit(seat, new_cards)
          seat = (seat + 1) % 4

      # Sanity check
      for p in players:
          assert(p.hand.size() == 13, "Player %d has %d cards, expected 13" % [p.seat_index, p.hand.size()])

      _set_state(RoundState.PLAYER_TURN)
      # Trump selector leads the first trick
      current_player_seat = trump_selector_seat
      current_trick = Trick.new(trump_suit)
      _do_player_turn()

  func _do_player_turn() -> void:
      var player := players[current_player_seat]
      var valid := player.hand.get_valid_cards(current_trick.led_suit, trump_suit)
      turn_started.emit(current_player_seat, valid)
      if not player.is_human:
          _schedule_ai_action()

  func _schedule_ai_action() -> void:
      _ai_pending = true
      _ai_timer = randf_range(AI_DELAY_MIN, AI_DELAY_MAX)

  ## Called each frame from a Node that owns this RoundManager via _process(delta)
  func tick(delta: float) -> void:
      if not _ai_pending:
          return
      _ai_timer -= delta
      if _ai_timer <= 0.0:
          _ai_pending = false
          _execute_ai_action()

  func _execute_ai_action() -> void:
      match state:
          RoundState.TRUMP_SELECTION:
              ai_select_trump()
          RoundState.PLAYER_TURN:
              _ai_play_card()

  func _ai_play_card() -> void:
      var ai := players[current_player_seat] as AIPlayer
      var valid := ai.hand.get_valid_cards(current_trick.led_suit, trump_suit)
      var partner_seat := (current_player_seat + 2) % 4  # partner is across
      var card := ai.choose_card(valid, current_trick, partner_seat)
      play_card(current_player_seat, card)

  ## Called by human UI with the card the human chose to play.
  func play_card(seat: int, card: Card) -> void:
      assert(seat == current_player_seat, "Not this player's turn")
      players[seat].hand.remove_card(card)
      current_trick.play_card(seat, card)
      card_played_signal.emit(seat, card)

      if current_trick.is_complete():
          _resolve_trick()
      else:
          current_player_seat = (current_player_seat + 1) % 4
          _set_state(RoundState.PLAYER_TURN)

  func _resolve_trick() -> void:
      _set_state(RoundState.TRICK_RESOLUTION)
      var winner_seat := current_trick.get_winner_index()
      var winner_team := 0 if winner_seat in [0, 1] else 1
      books[winner_team] += 1
      trick_completed.emit(winner_seat, books.duplicate())

      if books[0] >= BOOKS_TO_WIN or books[1] >= BOOKS_TO_WIN:
          var winning_team := 0 if books[0] >= BOOKS_TO_WIN else 1
          _set_state(RoundState.ROUND_OVER)
          round_ended.emit(winning_team)
      else:
          # Winner leads next trick
          current_player_seat = winner_seat
          current_trick = Trick.new(trump_suit)
          _set_state(RoundState.PLAYER_TURN)
  ```

- [ ] **Step 2: Run project and check debug output for errors**

  Use `mcp__godot__run_project` + `mcp__godot__get_debug_output`.
  Expected: no parse errors.

---

## Task 8: game_state.gd Autoload — Session State Machine

**Files:**
- Modify: `autoloads/game_state.gd` (replace stub with full implementation)

- [ ] **Step 1: Write game_state.gd**

  Write `autoloads/game_state.gd`:
  ```gdscript
  extends Node

  signal session_started()
  signal round_started(dealer_seat: int, trump_selector_seat: int)
  signal round_ended_session(winning_team: int, session_wins: Array)
  signal game_over()

  var round_manager: RoundManager
  var players: Array[Player] = []
  var session_wins: Array[int] = [0, 0]  # [team0, team1]
  var dealer_seat: int = 0
  ## Tracks which team dealt last round (for dealer rotation)
  var _last_dealing_team: int = -1
  var _dealer_within_team: Dictionary = {0: 0, 1: 2}  # team -> current dealer seat

  const SEAT_NAMES := ["You", "North", "West", "East"]

  func _ready() -> void:
      round_manager = RoundManager.new()
      round_manager.round_ended.connect(_on_round_ended)

  func _process(delta: float) -> void:
      round_manager.tick(delta)

  ## Call to begin a new session (resets session wins, randomizes first dealer).
  func start_session() -> void:
      session_wins = [0, 0]
      _setup_players()
      dealer_seat = randi() % 4
      _last_dealing_team = 0 if dealer_seat in [0, 1] else 1
      _dealer_within_team[_last_dealing_team] = dealer_seat
      session_started.emit()
      _start_round()

  func _setup_players() -> void:
      players.clear()
      # Seat 0 = human (bottom)
      players.append(Player.new(0, "You", true))
      # Seats 1, 2, 3 = AI
      players.append(AIPlayer.new(1, "North"))
      players.append(AIPlayer.new(2, "West"))
      players.append(AIPlayer.new(3, "East"))

  func _start_round() -> void:
      round_started.emit(dealer_seat, (dealer_seat + 1) % 4)
      round_manager.start_round(players, dealer_seat)

  func _on_round_ended(winning_team: int) -> void:
      session_wins[winning_team] += 1
      round_ended_session.emit(winning_team, session_wins.duplicate())
      # Losing team deals next round
      var losing_team := 1 - winning_team
      _rotate_dealer(losing_team)

  ## Rotate dealer within the losing team. Alternate between the two seats.
  func _rotate_dealer(losing_team: int) -> void:
      var current_dealer := _dealer_within_team[losing_team]
      # The two seats for the losing team
      var team_seats := [0, 1] if losing_team == 0 else [2, 3]
      var other_seat := team_seats[0] if current_dealer == team_seats[1] else team_seats[1]
      _dealer_within_team[losing_team] = other_seat
      dealer_seat = other_seat
      _last_dealing_team = losing_team

  func start_next_round() -> void:
      _start_round()

  ## Convenience accessors for UI
  func get_trump_suit() -> Card.Suit:
      return round_manager.trump_suit

  func get_books() -> Array:
      return round_manager.books.duplicate()

  func get_player(seat: int) -> Player:
      return players[seat] if seat < players.size() else null

  func get_round_manager() -> RoundManager:
      return round_manager
  ```

- [ ] **Step 2: Run project and check debug output for errors**

  Use `mcp__godot__run_project` + `mcp__godot__get_debug_output`.
  Expected: no parse errors for game_state.gd or round_manager.gd.

---

## Task 9: card.tscn — Visual Card Scene

**Files:**
- Create: `scenes/card.tscn`
- Create: `scripts/ui/card_ui.gd`

The visual card is a Control node with a Label showing rank+suit, color-coded by suit,
and state for highlighted / dimmed.

- [ ] **Step 1: Write card_ui.gd**

  Write `scripts/ui/card_ui.gd`:
  ```gdscript
  extends PanelContainer

  @onready var rank_label: Label = $VBox/RankLabel
  @onready var suit_label: Label = $VBox/SuitLabel

  var card_data: Card = null
  var _is_valid: bool = true
  var _is_selected: bool = false

  signal card_tapped(card: Card)

  const SUIT_COLORS := {
      Card.Suit.SPADES: Color.BLACK,
      Card.Suit.CLUBS: Color.BLACK,
      Card.Suit.HEARTS: Color(0.8, 0.1, 0.1),
      Card.Suit.DIAMONDS: Color(0.8, 0.1, 0.1)
  }

  func setup(c: Card, face_up: bool = true) -> void:
      card_data = c
      if face_up:
          _show_face()
      else:
          _show_back()

  func _show_face() -> void:
      rank_label.text = Card.RANK_NAMES[card_data.rank]
      suit_label.text = Card.SUIT_SYMBOLS[card_data.suit]
      var color := SUIT_COLORS[card_data.suit]
      rank_label.add_theme_color_override("font_color", color)
      suit_label.add_theme_color_override("font_color", color)

  func _show_back() -> void:
      rank_label.text = ""
      suit_label.text = "🂠"
      rank_label.add_theme_color_override("font_color", Color.WHITE)
      suit_label.add_theme_color_override("font_color", Color.DARK_BLUE)

  func set_valid(valid: bool) -> void:
      _is_valid = valid
      modulate.a = 1.0 if valid else 0.4

  func set_selected(selected: bool) -> void:
      _is_selected = selected
      # Move card up slightly when selected
      position.y = -20 if selected else 0

  func _gui_input(event: InputEvent) -> void:
      if event is InputEventMouseButton and event.pressed:
          if _is_valid and card_data != null:
              card_tapped.emit(card_data)
      if event is InputEventScreenTouch and event.pressed:
          if _is_valid and card_data != null:
              card_tapped.emit(card_data)
  ```

- [ ] **Step 2: Create card.tscn via MCP**

  Use `mcp__godot__create_scene`:
  - `projectPath`: `C:/Users/randy/Documents/Code/trump-card-game`
  - `scenePath`: `scenes/card.tscn`
  - `rootNodeType`: `PanelContainer`

  Use `mcp__godot__add_node` to add `VBoxContainer` named `VBox` as child of root, then add two `Label` nodes named `RankLabel` and `SuitLabel` as children of VBox.

  Add script to root: set `properties` on root with `script` = `res://scripts/ui/card_ui.gd`.

  Use `mcp__godot__save_scene`.

- [ ] **Step 3: Run project and screenshot**

  Create a temporary test scene that instantiates a card and calls `setup()` with Ace of Spades.
  Use `mcp__godot__run_project`, then check debug for errors.

---

## Task 10: game_table.tscn — Main Game Scene (Layout + HUD)

**Files:**
- Create: `scenes/game_table.tscn`
- Create: `scripts/ui/game_table_ui.gd`

Layout (portrait 390×844):
- Bottom hand area: HBoxContainer at y=720, centered, for human cards
- Top hand area: HBoxContainer at y=20, centered, for partner (face-down)
- Left hand area: VBoxContainer at x=10, centered vertically, for left opponent
- Right hand area: VBoxContainer at x=340, centered vertically, for right opponent
- Center trick area: GridContainer (2×2) at center (195, 380)
- HUD: top bar with trump label, book counter, session wins
- Player name labels at each seat

- [ ] **Step 1: Write game_table_ui.gd**

  Write `scripts/ui/game_table_ui.gd`:
  ```gdscript
  extends Control

  @onready var bottom_hand: HBoxContainer = $BottomHand
  @onready var top_hand: HBoxContainer = $TopHand
  @onready var left_hand: VBoxContainer = $LeftHand
  @onready var right_hand: VBoxContainer = $RightHand
  @onready var trick_area: GridContainer = $TrickArea
  @onready var trump_label: Label = $HUD/TrumpLabel
  @onready var books_label: Label = $HUD/BooksLabel
  @onready var session_label: Label = $HUD/SessionLabel
  @onready var turn_indicator: Label = $HUD/TurnIndicator
  @onready var trump_selector_overlay: Control = $TrumpSelectorOverlay
  @onready var win_screen_overlay: Control = $WinScreenOverlay

  const CardScene := preload("res://scenes/card.tscn")
  const HAND_CONTAINERS := {0: "bottom_hand", 1: "top_hand", 2: "left_hand", 3: "right_hand"}

  var _selected_card: Card = null
  var _current_valid_cards: Array[Card] = []

  func _ready() -> void:
      _connect_signals()
      GameState.start_session()

  func _connect_signals() -> void:
      var rm := GameState.get_round_manager()
      rm.hand_dealt.connect(_on_hand_dealt)
      rm.trump_selection_needed.connect(_on_trump_selection_needed)
      rm.trump_declared.connect(_on_trump_declared)
      rm.turn_started.connect(_on_turn_started)
      rm.card_played_signal.connect(_on_card_played)
      rm.trick_completed.connect(_on_trick_completed)
      rm.round_ended.connect(_on_round_ended)

  func _get_hand_container(seat: int) -> BoxContainer:
      match seat:
          0: return bottom_hand
          1: return top_hand
          2: return left_hand
          3: return right_hand
      return null

  func _on_hand_dealt(seat: int, cards: Array) -> void:
      var container := _get_hand_container(seat)
      var face_up := (seat == 0)
      for card in cards:
          var card_node := CardScene.instantiate() as PanelContainer
          var ui := card_node as Node  # gets card_ui.gd script
          ui.call("setup", card, face_up)
          if face_up:
              ui.connect("card_tapped", _on_card_tapped)
          container.add_child(card_node)

  func _on_trump_selection_needed(seat: int, initial_cards: Array) -> void:
      if seat == 0:
          # Human trump selection
          trump_selector_overlay.call("show_for_human", initial_cards)
          trump_selector_overlay.visible = true
      # AI handled by RoundManager timer

  func _on_trump_declared(suit: Card.Suit) -> void:
      trump_selector_overlay.visible = false
      trump_label.text = "Trump: " + Card.SUIT_NAMES[suit] + " " + Card.SUIT_SYMBOLS[suit]

  func _on_turn_started(seat: int, valid_cards: Array) -> void:
      _current_valid_cards = valid_cards
      turn_indicator.text = GameState.get_player(seat).display_name + "'s turn"
      if seat == 0:
          _highlight_valid_cards(valid_cards)

  func _highlight_valid_cards(valid_cards: Array) -> void:
      for child in bottom_hand.get_children():
          var ui: Node = child
          var card_data: Card = ui.get("card_data")
          if card_data != null:
              ui.call("set_valid", card_data in valid_cards)

  func _on_card_tapped(card: Card) -> void:
      if card not in _current_valid_cards:
          return
      if _selected_card == card:
          # Second tap = confirm play
          _play_selected_card()
      else:
          # First tap = select
          if _selected_card != null:
              _deselect_card(_selected_card)
          _selected_card = card
          _select_card(card)

  func _select_card(card: Card) -> void:
      for child in bottom_hand.get_children():
          if child.get("card_data") == card:
              child.call("set_selected", true)

  func _deselect_card(card: Card) -> void:
      for child in bottom_hand.get_children():
          if child.get("card_data") == card:
              child.call("set_selected", false)

  func _play_selected_card() -> void:
      var card := _selected_card
      _selected_card = null
      _clear_hand_highlight()
      GameState.get_round_manager().play_card(0, card)

  func _clear_hand_highlight() -> void:
      for child in bottom_hand.get_children():
          child.call("set_valid", true)
          child.call("set_selected", false)

  func _on_card_played(seat: int, card: Card) -> void:
      # Remove card from hand display
      var container := _get_hand_container(seat)
      for child in container.get_children():
          if child.get("card_data") == card:
              child.queue_free()
              break
      # Add card to trick area
      var trick_card := CardScene.instantiate()
      trick_card.call("setup", card, true)
      trick_area.add_child(trick_card)

  func _on_trick_completed(winner_seat: int, books: Array) -> void:
      books_label.text = "Books — You: %d | Opp: %d" % [books[0], books[1]]
      # Clear trick area after short delay (signal comes from RoundManager after resolve)
      await get_tree().create_timer(1.0).timeout
      for child in trick_area.get_children():
          child.queue_free()

  func _on_round_ended(winning_team: int) -> void:
      var wins := GameState.session_wins
      session_label.text = "Session — You: %d | Opp: %d" % [wins[0], wins[1]]
      win_screen_overlay.call("show_result", winning_team, wins)
      win_screen_overlay.visible = true
  ```

- [ ] **Step 2: Create game_table.tscn via MCP**

  Use `mcp__godot__create_scene`:
  - `projectPath`: `C:/Users/randy/Documents/Code/trump-card-game`
  - `scenePath`: `scenes/game_table.tscn`
  - `rootNodeType`: `Control`

  Then use `mcp__godot__add_node` for each child node:
  1. `HBoxContainer` named `BottomHand`, properties: `{"anchors_preset": 5, "offset_top": -100, "offset_bottom": 0}` — centered bottom
  2. `HBoxContainer` named `TopHand` — top center
  3. `VBoxContainer` named `LeftHand` — left center
  4. `VBoxContainer` named `RightHand` — right center
  5. `GridContainer` named `TrickArea`, properties: `{"columns": 2}` — center
  6. `HBoxContainer` named `HUD` — top bar
     - `Label` named `TrumpLabel` as child of HUD
     - `Label` named `BooksLabel` as child of HUD
     - `Label` named `SessionLabel` as child of HUD
     - `Label` named `TurnIndicator` as child of HUD
  7. `Control` named `TrumpSelectorOverlay` (initially hidden)
  8. `Control` named `WinScreenOverlay` (initially hidden)

  Set script on root node to `res://scripts/ui/game_table_ui.gd`.
  Use `mcp__godot__save_scene`.

- [ ] **Step 3: Run project and take screenshot**

  Use `mcp__godot__run_project` with `scene = "scenes/game_table.tscn"`.
  Use `mcp__godot__get_debug_output`.

  **Verify:**
  - No script errors
  - Session starts (round_manager gets `start_round` called)
  - Trump selection triggers for trump selector seat

  If there are errors in debug output, fix them before proceeding.

---

## Task 11: trump_selector.tscn + trump_selector_ui.gd

**Files:**
- Create: `scenes/ui/trump_selector.tscn`
- Create: `scripts/ui/trump_selector_ui.gd`

- [ ] **Step 1: Write trump_selector_ui.gd**

  Write `scripts/ui/trump_selector_ui.gd`:
  ```gdscript
  extends Control

  @onready var cards_container: HBoxContainer = $CardsContainer
  @onready var spades_btn: Button = $SuitButtons/SpadesBtn
  @onready var hearts_btn: Button = $SuitButtons/HeartsBtn
  @onready var diamonds_btn: Button = $SuitButtons/DiamondsBtn
  @onready var clubs_btn: Button = $SuitButtons/ClubsBtn
  @onready var prompt_label: Label = $PromptLabel

  const CardScene := preload("res://scenes/card.tscn")

  func _ready() -> void:
      spades_btn.pressed.connect(func(): _on_suit_chosen(Card.Suit.SPADES))
      hearts_btn.pressed.connect(func(): _on_suit_chosen(Card.Suit.HEARTS))
      diamonds_btn.pressed.connect(func(): _on_suit_chosen(Card.Suit.DIAMONDS))
      clubs_btn.pressed.connect(func(): _on_suit_chosen(Card.Suit.CLUBS))

  func show_for_human(initial_cards: Array) -> void:
      prompt_label.text = "Choose Trump Suit"
      _populate_cards(initial_cards)
      spades_btn.disabled = false
      hearts_btn.disabled = false
      diamonds_btn.disabled = false
      clubs_btn.disabled = false

  func _populate_cards(cards: Array) -> void:
      for child in cards_container.get_children():
          child.queue_free()
      for card in cards:
          var card_node := CardScene.instantiate()
          card_node.call("setup", card, true)
          card_node.call("set_valid", false)  # not tappable during trump selection
          cards_container.add_child(card_node)

  func _on_suit_chosen(suit: Card.Suit) -> void:
      GameState.get_round_manager().declare_trump(suit)
  ```

- [ ] **Step 2: Create trump_selector.tscn via MCP**

  Use `mcp__godot__create_scene`:
  - `scenePath`: `scenes/ui/trump_selector.tscn`
  - `rootNodeType`: `Control`

  Add nodes:
  1. `Label` named `PromptLabel`
  2. `HBoxContainer` named `CardsContainer`
  3. `HBoxContainer` named `SuitButtons`
     - `Button` named `SpadesBtn`, properties: `{"text": "♠ Spades"}`
     - `Button` named `HeartsBtn`, properties: `{"text": "♥ Hearts"}`
     - `Button` named `DiamondsBtn`, properties: `{"text": "♦ Diamonds"}`
     - `Button` named `ClubsBtn`, properties: `{"text": "♣ Clubs"}`

  Set script to `res://scripts/ui/trump_selector_ui.gd`.
  Save scene.

- [ ] **Step 3: Instantiate trump_selector.tscn inside game_table.tscn**

  The `TrumpSelectorOverlay` Control in game_table.tscn should be replaced with an
  instantiated trump_selector.tscn. Edit `scenes/game_table.tscn` or re-create the
  overlay as an instance. Alternatively, load it dynamically in game_table_ui.gd:

  In `game_table_ui.gd`, add at top:
  ```gdscript
  const TrumpSelectorScene := preload("res://scenes/ui/trump_selector.tscn")
  ```
  And in `_ready()`, replace the static overlay reference approach:
  ```gdscript
  # In _ready(), after _connect_signals():
  var ts := TrumpSelectorScene.instantiate()
  ts.visible = false
  add_child(ts)
  trump_selector_overlay = ts
  ```
  Remove the `@onready` line for trump_selector_overlay from the script.

---

## Task 12: win_screen.tscn + win_screen_ui.gd

**Files:**
- Create: `scenes/ui/win_screen.tscn`
- Create: `scripts/ui/win_screen_ui.gd`

- [ ] **Step 1: Write win_screen_ui.gd**

  Write `scripts/ui/win_screen_ui.gd`:
  ```gdscript
  extends Control

  @onready var result_label: Label = $ResultLabel
  @onready var session_label: Label = $SessionLabel
  @onready var next_round_btn: Button = $Buttons/NextRoundBtn
  @onready var main_menu_btn: Button = $Buttons/MainMenuBtn

  func _ready() -> void:
      next_round_btn.pressed.connect(_on_next_round)
      main_menu_btn.pressed.connect(_on_main_menu)

  func show_result(winning_team: int, session_wins: Array) -> void:
      if winning_team == 0:
          result_label.text = "Your Team Wins!"
          result_label.add_theme_color_override("font_color", Color(0.1, 0.8, 0.1))
      else:
          result_label.text = "Opponents Win!"
          result_label.add_theme_color_override("font_color", Color(0.8, 0.1, 0.1))
      session_label.text = "Session — You: %d | Opponents: %d" % [session_wins[0], session_wins[1]]

  func _on_next_round() -> void:
      visible = false
      GameState.start_next_round()

  func _on_main_menu() -> void:
      # For now, restart the session
      visible = false
      GameState.start_session()
  ```

- [ ] **Step 2: Create win_screen.tscn via MCP**

  Use `mcp__godot__create_scene`:
  - `scenePath`: `scenes/ui/win_screen.tscn`
  - `rootNodeType`: `PanelContainer`

  Add:
  1. `VBoxContainer` named `VBox`
     - `Label` named `ResultLabel`, properties: `{"text": "Result"}`
     - `Label` named `SessionLabel`, properties: `{"text": "Session"}`
     - `HBoxContainer` named `Buttons`
       - `Button` named `NextRoundBtn`, properties: `{"text": "Next Round"}`
       - `Button` named `MainMenuBtn`, properties: `{"text": "Main Menu"}`

  Set script to `res://scripts/ui/win_screen_ui.gd`. Save scene.

- [ ] **Step 3: Wire win_screen into game_table_ui.gd (same dynamic-instantiation pattern)**

  In `game_table_ui.gd`, add:
  ```gdscript
  const WinScreenScene := preload("res://scenes/ui/win_screen.tscn")
  ```
  In `_ready()`:
  ```gdscript
  var ws := WinScreenScene.instantiate()
  ws.visible = false
  add_child(ws)
  win_screen_overlay = ws
  ```
  Remove `@onready` line for `win_screen_overlay`.

---

## Task 13: Full Integration Test — Screenshot Verification

- [ ] **Step 1: Run the full game_table scene**

  Use `mcp__godot__run_project` with `projectPath = "C:/Users/randy/Documents/Code/trump-card-game"`.

- [ ] **Step 2: Capture and check debug output**

  Use `mcp__godot__get_debug_output`. Verify:
  - No script parse errors
  - No "Node not found" errors for @onready nodes
  - No assertion failures

- [ ] **Step 3: Add a screenshot autoload helper**

  If visual verification is needed, add this to `autoloads/game_state.gd` `_ready()`:
  ```gdscript
  # Debug: auto-screenshot after 2 seconds
  if OS.is_debug_build():
      get_tree().create_timer(2.0).timeout.connect(func():
          var img := get_viewport().get_texture().get_image()
          img.save_png("user://debug_screenshot.png")
          print("Screenshot saved to: ", OS.get_user_data_dir() + "/debug_screenshot.png")
      )
  ```
  Run again, check debug output for the screenshot path, then read that file.

- [ ] **Step 4: Verify layout against CLAUDE.md**

  Check the screenshot against these CLAUDE.md requirements:
  - [ ] Human hand visible at bottom
  - [ ] 3 opponent hand areas present (top, left, right)
  - [ ] Center trick area exists (empty at start)
  - [ ] HUD shows trump, books, session wins, turn indicator
  - [ ] Trump selector overlay appears when trump selection is needed
  - [ ] Win screen hidden at start

- [ ] **Step 5: Fix any layout issues before marking complete**

  Any misalignment, missing nodes, or wrong card counts must be fixed with a re-run and new screenshot before declaring this task done.

---

## Self-Review Against CLAUDE.md

### Spec Coverage Check

| CLAUDE.md Requirement | Task |
|----------------------|------|
| 4 players, 2 teams (0+1 vs 2+3) | Task 6, 8 |
| Trump selector = left of dealer | Task 7 (dealer+1 % 4) |
| Losing team deals next round | Task 8 (_on_round_ended) |
| Deal 5 to trump selector first | Task 6 (_do_deal_initial) |
| Trump selector must choose suit (no pass) | Task 11 (buttons only, no skip) |
| All 4 players end with 13 cards | Task 6 (_do_deal_remaining, assert) |
| Must follow led suit | Task 4 (get_valid_cards) |
| Trump beats all non-trump | Task 2 (Card.beats) |
| Higher trump beats lower trump | Task 2 (Card.beats, both trump → rank compare) |
| Trump can be led any time | Task 4 (no restriction in get_valid_cards) |
| Trump selector leads first trick | Task 6 (current_player_seat = trump_selector_seat) |
| Trick winner leads next | Task 6 (_resolve_trick: current_player_seat = winner_seat) |
| 7 books = immediate win | Task 6 (books[x] >= BOOKS_TO_WIN check after every trick) |
| No book carry-over | Task 6 (books reset to [0,0] in start_round) |
| Dealer rotates within losing team | Task 8 (_rotate_dealer) |
| Session wins persist | Task 8 (session_wins array, never reset unless new session) |
| Invalid cards dimmed/not playable | Task 9 (set_valid dimming), Task 5 (valid_cards filter) |
| AI follows suit rules | Task 5 (get_valid_cards used by AIPlayer.choose_card) |
| AI picks most-cards suit for trump | Task 5 (dominant_suit) |
| AI delay 0.5–1.0s | Task 6 (AI_DELAY_MIN/MAX constants) |
| Portrait mode | Task 1 (window/handheld/orientation=1 in project.godot) |
| Screenshot verification each milestone | Tasks 2, 3, 4, 5, 6, 7, 8, 10, 13 |

### Known Gaps (Not In Scope For This Plan)
- `main_menu.tscn` — not needed to play single player
- `mode_select.tscn` — game goes directly to table
- Sound effects — deferred (CLAUDE.md priority 8)
- Multiplayer — explicitly out of scope
- Turn timer — multiplayer only per CLAUDE.md
- Score display as separate scene — inlined in HUD for now

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-04-trump-card-game-bootstrap.md`. Two execution options:

**1. Subagent-Driven (recommended)** — Fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
