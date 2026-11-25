
extends Node2D

@onready var video = $VideoStreamPlayer
@onready var menu = $MainMenu

@onready var background = $MainMenu/Background
@onready var play_button = $MainMenu/PlayButton
@onready var credits_button = $MainMenu/CreditsButton

@onready var play_screen = $MainMenu/PlayScreen
@onready var credits_screen = $MainMenu/CreditsScreen
@onready var credits_back_button = $MainMenu/CreditsScreen/CreditsBackButton


func _ready():
	menu.hide()
	play_screen.hide()
	credits_screen.hide()

	video.finished.connect(_on_video_finished)

	play_button.pressed.connect(_on_play_pressed)
	credits_button.pressed.connect(_on_credits_pressed)
	credits_back_button.pressed.connect(_on_credits_back_pressed)

	video.play()


func _on_video_finished():
	video.hide()
	menu.show()

	background.show()
	play_button.show()
	credits_button.show()


func _on_play_pressed():
	get_tree().change_scene_to_file("res://main.tscn")


func _on_credits_pressed():
	background.hide()
	play_button.hide()
	credits_button.hide()

	credits_screen.show()


func _on_credits_back_pressed():
	credits_screen.hide()

	background.show()
	play_button.show()
	credits_button.show()
