class_name RidingInput
extends RefCounted

## Turn request, positive = turn left. Combines the stick and stance.
var turn := 0.0
var sharp_turn := 0.0
## Foot brake amount 0..1.
var brake := 0.0
var push_pressed := false
var push_held := false
## Powerslide held and which way to slide.
var slide := false
var slide_direction := 0.0
## Manual balance, positive = tail down.
var balance := 0.0
## Any stick or button activity this tick (for the no-input friction timer).
var active := false
## Rider centre-of-mass height above the deck (from the rig), for pumping.
var com_height := 0.8
## The player is driving the crouch (pumps count in full).
var player_pumping := false
