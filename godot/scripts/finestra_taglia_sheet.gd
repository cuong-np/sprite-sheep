extends Window
## Importa uno sprite sheet a celle regolari e salva ogni frame come PNG.

@onready var _anteprima: TextureRect = %Anteprima
@onready var _percorso_lbl: Label = %PercorsoImmagine
@onready var _info: Label = %InfoGriglia
@onready var _colonne: SpinBox = %Colonne
@onready var _righe: SpinBox = %Righe
@onready var _numero_frame: SpinBox = %NumeroFrame
@onready var _ritaglia: CheckBox = %RitagliaCheck
@onready var _percorso_uscita_lbl: Label = %PercorsoUscita
@onready var _btn_esporta: Button = %Esporta
@onready var _dialogo_file: FileDialog = %FileDialog
@onready var _dialogo_cartella: FileDialog = %CartellaDialog

var _immagine: Image
var _percorso: String = ""
var _cartella_uscita: String = ""


func _ready() -> void:
	%ScegliImmagine.pressed.connect(_scegli_immagine)
	%ScegliCartella.pressed.connect(_scegli_cartella)
	_dialogo_file.file_selected.connect(_carica_immagine)
	_dialogo_cartella.dir_selected.connect(_seleziona_cartella)
	_colonne.value_changed.connect(_griglia_cambiata)
	_righe.value_changed.connect(_griglia_cambiata)
	_numero_frame.value_changed.connect(func(_valore: float) -> void: _aggiorna_info())
	_btn_esporta.pressed.connect(_esporta)
	close_requested.connect(hide)


func _scegli_immagine() -> void:
	_dialogo_file.popup_centered()


func _scegli_cartella() -> void:
	_dialogo_cartella.popup_centered()


func _carica_immagine(percorso: String) -> void:
	var caricata := Image.load_from_file(percorso)
	if caricata == null or caricata.is_empty():
		_info.text = tr("Impossibile leggere questa immagine.")
		return
	_immagine = caricata
	_percorso = percorso
	_cartella_uscita = ""
	_percorso_lbl.text = percorso.get_file()
	_percorso_uscita_lbl.text = tr("Accanto allo sheet, in una nuova cartella")
	_anteprima.texture = ImageTexture.create_from_image(_immagine)
	_btn_esporta.disabled = false
	_aggiorna_info(true)


func _seleziona_cartella(percorso: String) -> void:
	_cartella_uscita = percorso
	_percorso_uscita_lbl.text = percorso


func _griglia_cambiata(_valore: float) -> void:
	_aggiorna_info(true)


func _aggiorna_info(ricalcola_frame: bool = false) -> void:
	if _immagine == null or _immagine.is_empty():
		return
	var colonne := int(_colonne.value)
	var righe := int(_righe.value)
	var massimo := colonne * righe
	_numero_frame.max_value = massimo
	if ricalcola_frame:
		var rilevati := _ultimo_frame_occupato(colonne, righe)
		_numero_frame.value = rilevati if rilevati > 0 else massimo
	else:
		_numero_frame.value = clampi(int(_numero_frame.value), 1, massimo)

	var cella_x := _immagine.get_width() / colonne
	var cella_y := _immagine.get_height() / righe
	var avviso := ""
	if _immagine.get_width() % colonne != 0 or _immagine.get_height() % righe != 0:
		avviso = " · " + tr("Le dimensioni non si dividono esattamente nella griglia.")
	_info.text = tr("Foglio %d × %d px · celle %d × %d px · %d celle occupate") % [
		_immagine.get_width(), _immagine.get_height(), cella_x, cella_y,
		int(_numero_frame.value)] + avviso


## In PNG trasparenti ignora le celle vuote in coda, come l'ultima cella
## vuota del foglio 5×5 con 24 frame. Il conteggio resta modificabile.
func _ultimo_frame_occupato(colonne: int, righe: int) -> int:
	var lato_x := _immagine.get_width() / colonne
	var lato_y := _immagine.get_height() / righe
	var ultimo := 0
	for i in colonne * righe:
		var r := int(i / colonne)
		var c := i % colonne
		var cella := _immagine.get_region(Rect2i(c * lato_x, r * lato_y,
			lato_x, lato_y))
		if cella.get_used_rect().has_area():
			ultimo = i + 1
	return ultimo


func _esporta() -> void:
	if _immagine == null or _immagine.is_empty() or _percorso == "":
		return
	var colonne := int(_colonne.value)
	var righe := int(_righe.value)
	var quanti := int(_numero_frame.value)
	if colonne < 1 or righe < 1 or quanti < 1 or quanti > colonne * righe:
		_info.text = tr("Controlla colonne, righe e numero di frame.")
		return
	if _immagine.get_width() % colonne != 0 or _immagine.get_height() % righe != 0:
		_info.text = tr("Le dimensioni non si dividono esattamente nella griglia.")
		return

	var destinazione := _cartella_uscita
	if destinazione == "":
		destinazione = _percorso.get_basename() + "_frames_png"
	var err := DirAccess.make_dir_recursive_absolute(destinazione)
	if err != OK:
		_info.text = tr("Impossibile creare la cartella di uscita.")
		return

	var lato_x := _immagine.get_width() / colonne
	var lato_y := _immagine.get_height() / righe
	for i in quanti:
		var r := int(i / colonne)
		var c := i % colonne
		var frame := _immagine.get_region(Rect2i(c * lato_x, r * lato_y,
			lato_x, lato_y))
		if _ritaglia.button_pressed:
			var area := frame.get_used_rect()
			if area.has_area():
				frame = frame.get_region(area)
		err = frame.save_png(destinazione.path_join("frame_%03d.png" % (i + 1)))
		if err != OK:
			_info.text = tr("Impossibile salvare i frame PNG.")
			return

	_info.text = tr("Esportati %d frame in: %s") % [quanti, destinazione]
	OS.shell_open(destinazione)
