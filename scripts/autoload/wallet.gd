extends Node
## The player's money, in Australian dollars (autoload: Wallet).

signal changed(balance: int, delta: int)

const STARTING_BALANCE := 400

var balance := STARTING_BALANCE
## Lifetime earnings, for stats and tier checks.
var total_earned := 0


func _ready() -> void:
	SaveGame.register("wallet", self)


func earn(amount: int, _reason := "") -> void:
	balance += amount
	total_earned += amount
	changed.emit(balance, amount)


func can_afford(amount: int) -> bool:
	return balance >= amount


## Returns false (and spends nothing) if the player can't afford it.
func spend(amount: int, _reason := "") -> bool:
	if amount > balance:
		return false
	balance -= amount
	changed.emit(balance, -amount)
	return true


func save_state() -> Dictionary:
	return {"balance": balance, "total_earned": total_earned}


func load_state(data: Dictionary) -> void:
	balance = int(data.get("balance", STARTING_BALANCE))
	total_earned = int(data.get("total_earned", 0))
	changed.emit(balance, 0)
