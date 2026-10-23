extends PanelContainer
## Mostra l'ultimo risultato: animazione riprodotta dal foglio, foglio intero,
## e i numeri veri (frame, fps reali, durata).
##
## L'animazione non viene letta dalla GIF: Godot non le decodifica. Si ritagliano
## le celle dal foglio PNG, che e' comunque la sorgente da cui la GIF e' nata.

@onready var _vuoto: Label = %Vuoto
@onready var _contenuto: VBoxContainer = %Contenuto
@onready var _anteprima: TextureRect = %Anteprima
@onready var _foglio: TextureRect = %Foglio
@onready var _pausa: Button = %PausaButton
@onready var _fps: HSlider = %FpsSlider
@onready var _fps_lbl: Label = %FpsLabel
@onready var _dati: RichTextLabel = %DatiLabel
@onready var _btn_cartella: Button = %CartellaButton
@onready var _btn_esporta: Button = %EsportaFrameButton
@onready var _btn_copia: Button = %CopiaPercorsoButton

var _celle: Array[AtlasTexture] = []
var _i := 0
var _accumulo := 0.0
var _in_pausa := false
var _cartella := ""
var _log := ""
var _ultimo_sheet: Dictionary = {}
var _immagine_sheet: Image
## Creato da codice e non nella scena: e' un fratello di "Apri cartella" e
## vive o muore con lui, quindi basta metterlo subito dopo.
var _btn_log := Button.new()
## La riga discreta di Ko-fi sotto il risultato: quando mostrarla lo decide lei.
var _invito := InvitoKofi.new()


func _ready() -> void:
	set_process(false)
	_pausa.pressed.connect(_alterna_pausa)
	_fps.value_changed.connect(func(v: float) -> void: _fps_lbl.text = "%d fps" % int(v))
	_btn_cartella.pressed.connect(func() -> void:
		if _cartella != "":
			OS.shell_open(_cartella))
	_btn_log.text = tr("Apri log")
	_btn_log.tooltip_text = tr("Parametri della generazione: prompt, modello, seed, tempi, scontorno")
	_btn_log.pressed.connect(func() -> void:
		if _log != "":
			OS.shell_open(_log))
	_btn_cartella.add_sibling(_btn_log)
	_btn_esporta.pressed.connect(_esporta_frame_png)
	_contenuto.add_child(_invito)
	_btn_copia.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(_cartella)
		_btn_copia.text = tr("Copiato"))


## `stato` e' quello restituito dal sidecar a fine lavoro.
func mostra(stato: Dictionary) -> void:
	var sh: Dictionary = stato.get("sheet", {})
	_ultimo_sheet = sh
	_cartella = str(stato.get("cartella", ""))
	# Il log puo' mancare (scrittura fallita, sidecar vecchio): meglio un
	# bottone spento che uno che apre il nulla.
	var lg = stato.get("log", null)
	_log = str(lg) if lg != null and FileAccess.file_exists(str(lg)) else ""
	_btn_log.disabled = _log == ""
	_btn_copia.text = tr("Copia percorso")

	var percorso: String = str(sh.get("percorso", ""))
	_btn_esporta.disabled = true
	if percorso == "" or not FileAccess.file_exists(percorso):
		# Il foglio e' su disco fuori da res://: se manca, meglio dirlo che
		# lasciare un riquadro vuoto senza spiegazione.
		_vuoto.text = tr("Foglio non trovato: %s") % percorso
		_vuoto.visible = true
		_contenuto.visible = false
		return

	var img := Image.load_from_file(percorso)
	if img == null:
		_vuoto.text = tr("Foglio illeggibile: %s") % percorso
		_vuoto.visible = true
		_contenuto.visible = false
		return

	_immagine_sheet = img
	var intero := ImageTexture.create_from_image(img)
	_foglio.texture = intero
	_ritaglia(intero, int(sh.get("colonne", 5)), int(sh.get("righe", 5)),
		int(sh.get("celle", 0)))
	_btn_esporta.disabled = _celle.is_empty()
	_btn_esporta.text = tr("Esporta frame PNG")

	var gf: Dictionary = stato.get("gif", {})
	_dati.text = "\n".join([
		tr("[b]%d[/b] frame · foglio %d x %d px")
			% [int(gf.get("frame", _celle.size())),
				int(sh.get("larghezza", img.get_width())),
				int(sh.get("altezza", img.get_height()))],
		tr("GIF: [b]%.1f fps[/b] reali, %.2f s")
			% [float(gf.get("fps_reale", 0)), float(gf.get("durata_s", 0))],
	])
	if stato.has("seed"):
		_dati.text += "
" + tr("Seed: [b]%d[/b]") % int(stato["seed"])
	_fps.value = maxf(1.0, float(gf.get("fps_reale", 12)))
	_fps_lbl.text = "%d fps" % int(_fps.value)

	_vuoto.visible = false
	_contenuto.visible = true
	_i = 0
	_accumulo = 0.0
	_in_pausa = false
	_pausa.text = tr("Pausa")
	set_process(true)
	# Solo qui, cioe' solo a generazione riuscita: dopo un errore o un
	# Annulla questo pannello non viene nemmeno chiamato.
	_invito.proponi()


## Esporta solo le celle effettive dello sheet, mantenendo tela e trasparenza.
## Una sottocartella evita di mischiare i PNG con sheet, GIF e log.
func _esporta_frame_png() -> void:
	if _cartella == "" or _celle.is_empty():
		return
	_btn_esporta.disabled = true
	var cartella_frame := _cartella.path_join("frames_png")
	var err := DirAccess.make_dir_recursive_absolute(cartella_frame)
	if err != OK:
		push_error("Impossibile creare la cartella dei frame: %s (errore %d)" % [cartella_frame, err])
		_btn_esporta.text = tr("Esportazione non riuscita")
		_btn_esporta.disabled = false
		return

	var colonne := maxi(1, int(_ultimo_sheet.get("colonne", 1)))
	var righe := maxi(1, int(_ultimo_sheet.get("righe", 1)))
	var lato_x := _immagine_sheet.get_width() / colonne
	var lato_y := _immagine_sheet.get_height() / righe
	var scritti := 0
	for i in _celle.size():
		var regione := Rect2i((i % colonne) * lato_x, int(i / colonne) * lato_y,
			lato_x, lato_y)
		var frame := _immagine_sheet.get_region(regione)
		var destinazione := cartella_frame.path_join("frame_%03d.png" % (i + 1))
		err = frame.save_png(destinazione)
		if err != OK:
			push_error("Impossibile salvare il frame: %s (errore %d)" % [destinazione, err])
			_btn_esporta.text = tr("Esportazione non riuscita")
			_btn_esporta.disabled = false
			return
		scritti += 1
	_btn_esporta.text = tr("Frame PNG esportati: %d") % scritti
	_btn_esporta.disabled = false
	OS.shell_open(cartella_frame)


func _ritaglia(intero: Texture2D, colonne: int, righe: int, n_frame: int) -> void:
	_celle.clear()
	colonne = maxi(1, colonne)
	righe = maxi(1, righe)
	var lc: int = intero.get_width() / colonne
	var la: int = intero.get_height() / righe
	var quante: int = n_frame if n_frame > 0 else colonne * righe
	for i in mini(quante, colonne * righe):
		var a := AtlasTexture.new()
		a.atlas = intero
		a.region = Rect2(float(i % colonne) * lc, float(i / colonne) * la, lc, la)
		_celle.append(a)


func _process(delta: float) -> void:
	if _in_pausa or _celle.is_empty():
		return
	_accumulo += delta
	var passo := 1.0 / maxf(1.0, _fps.value)
	if _accumulo < passo:
		return
	_accumulo = 0.0
	_i = (_i + 1) % _celle.size()
	_anteprima.texture = _celle[_i]


func _alterna_pausa() -> void:
	_in_pausa = not _in_pausa
	_pausa.text = tr("Riprendi") if _in_pausa else tr("Pausa")


## Torna allo stato iniziale quando parte una nuova generazione.
func pulisci() -> void:
	_invito.nascondi()
	set_process(false)
	_celle.clear()
	_btn_esporta.disabled = true
	_btn_esporta.text = tr("Esporta frame PNG")
	_immagine_sheet = null
	_ultimo_sheet.clear()
	_cartella = ""
	_anteprima.texture = null
	_foglio.texture = null
	_contenuto.visible = false
	_vuoto.text = "Qui compaiono l'animazione e il foglio appena pronti."
	_vuoto.visible = true
