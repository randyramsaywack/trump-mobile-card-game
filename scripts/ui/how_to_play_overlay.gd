extends Control

signal closed()

@onready var body: RichTextLabel = $Panel/VBox/Scroll/Body
@onready var close_button: Button = $Panel/VBox/CloseButton

const RULES_TEXT := "[b]The Game[/b]
Trump is a 4-player trick-taking card game. You and your partner (across the table) team up against the two opponents on your left and right. First team to 7 tricks wins the round.

[b]The Deal[/b]
The losing team deals each round. The player to the dealer's left (the [i]trump selector[/i]) gets 5 cards first and must pick one of the four suits as trump — no passing. Then dealing finishes clockwise until everyone has 13 cards.

[b]Trump[/b]
Trump beats everything. A higher trump beats a lower trump. You can lead trump whenever you want — it doesn't have to be \"broken\" first.

[b]Playing a Trick[/b]
The trump selector leads the first trick. Whoever wins a trick leads the next one. You [b]must[/b] follow the suit that was led if you can. If you can't, play whatever you want — trump to try to win, or dump a card you don't need.

[b]Winning a Trick[/b]
• If trump was played, the highest trump wins.
• Otherwise, the highest card of the led suit wins.
• Off-suit non-trump cards can never win.

[b]Card Ranks[/b]
A (high), K, Q, J, 10, 9, 8, 7, 6, 5, 4, 3, 2 (low)

[b]Winning the Round[/b]
First team to 7 tricks wins. The winning team picks trump next round; the losing team deals.

[b]Tips[/b]
• Watch which suits opponents can't follow — that tells you what they're out of.
• Save high trumps for tricks that matter.
• Don't waste a trump when your partner is already winning the trick."

func _ready() -> void:
	body.text = RULES_TEXT
	close_button.pressed.connect(_on_close_pressed)

func _on_close_pressed() -> void:
	visible = false
	closed.emit()
