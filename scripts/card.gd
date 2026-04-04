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
