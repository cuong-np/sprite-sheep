extends OptionButton
## Tendina che ricorda l'ultima scelta fra un avvio e l'altro.
##
## Serve al formato della clip e al margine intorno alla figura: chi fa sprite
## per un gioco usa sempre le stesse impostazioni, e riproporre il default a
## ogni avvio lo costringerebbe a ricambiarle ogni volta.
##
## Le chiavi sono quelle che il sidecar accetta (`parametri.FORMATI`,
## `inquadra.MARGINI`); le etichette sono testo da tradurre, e la tendina lo
## traduce da se', anche a lingua cambiata.

@export var chiavi: PackedStringArray = []
@export var etichette: PackedStringArray = []
@export var predefinita := ""
@export var memoria := ""

## Rete di sicurezza per le build in cui i valori salvati nella scena non
## arrivano allo script: senza chiavi, OptionButton resta vuoto e select(0)
## registra "item_count = 0" nel log dell'applicazione.
const RIPIEGO := {
	"FormatoOption": {
		"chiavi": ["1:1", "3:4", "4:3", "9:16", "16:9", "21:9"],
		"etichette": ["1:1 quadrato", "3:4 verticale", "4:3 orizzontale",
			"9:16 verticale alto", "16:9 orizzontale largo", "21:9 panoramico"],
		"predefinita": "1:1",
		"memoria": "user://formato.cfg",
	},
	"MargineOption": {
		"chiavi": ["nessuno", "normale", "ampio"],
		"etichette": ["Come lo sprite", "Normale: figura all'80%",
			"Ampio: figura al 68% (salti, colpi in alto)"],
		"predefinita": "nessuno",
		"memoria": "user://margine.cfg",
	},
}


func _ready() -> void:
	_applica_ripiego_se_manca()
	for i in chiavi.size():
		add_item(etichette[i] if i < etichette.size() else chiavi[i])
	if item_count > 0:
		var indice := chiavi.find(_ricordata())
		select(indice if indice >= 0 else 0)
	item_selected.connect(func(_i: int) -> void: _ricorda())
	if item_count == 0:
		push_error("Nessuna opzione configurata per %s." % name)


func _applica_ripiego_se_manca() -> void:
	if not chiavi.is_empty():
		return
	var dati: Dictionary = RIPIEGO.get(name, {})
	if dati.is_empty():
		return
	chiavi = PackedStringArray(dati["chiavi"])
	etichette = PackedStringArray(dati["etichette"])
	predefinita = dati["predefinita"]
	memoria = dati["memoria"]


func valore() -> String:
	if chiavi.is_empty():
		return predefinita
	return chiavi[clampi(selected, 0, chiavi.size() - 1)]


func _ricordata() -> String:
	return Memoria.leggi(memoria, predefinita)


func _ricorda() -> void:
	Memoria.scrivi(memoria, valore())
