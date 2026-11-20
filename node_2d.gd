
extends Node2D

@onready var video = $VideoStreamPlayer
@onready var menu = $MainMenu

func _ready():
	menu.hide()

	video.finished.connect(_on_video_finished)

	video.play()


func _on_video_finished():
	menu.show()
	menu.modulate.a = 0.0

	var tween = create_tween()
	tween.tween_property(menu, "modulate:a", 1.0, 2.0)
