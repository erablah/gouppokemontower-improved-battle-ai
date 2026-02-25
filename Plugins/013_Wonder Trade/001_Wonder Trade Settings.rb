#===============================================================================
# Wonder Trade
# By Dr.Doom76
#===============================================================================
module WonderTradeSettings
 # This is a list of Blocklisted Pokemon. These Pokemon will be considered for trade.
 # Format is [:POKEMON1, :POKEMON2]
 USE_BLOCKLIST = false
 
 BLOCKLIST_POKEMON = []
 
 # This is a list of Allowlisted Pokemon. These Pokemon will be pushed into the trade pool.
 # The first thing is the species of the Pokemon you want an extra "chance" of getting.
 # The second thing is the number of "chances" you wish to add.
 # The higher the number, the lower the rarity is going to be.
 # Format is as follows:
 #ALLOWLIST_POKEMON = {
 # :MELOETTA => 5,
 # :RATTATA => 10,
 # :PIKACHU => 30
 #  }

 USE_ALLOWLIST = false

 ALLOWLIST_POKEMON = {

}
 
 # Setting for Male and Female names. Names are randomly selected from one of the listed, if not otherwised defined.
 MALE_NAMES = [
  "누군가",
  "영",
  "진영",
  "진석",
  "영민",
  "세준"
]

FEMALE_NAMES = [
  "누군가"
]

# Settings for nick names. If true, it will randomly assign a nickname from the list below, if a nickname is not passed through an argument.
USE_NICKNAME = false

POKEMON_NICKNAMES = [
  "Bolt",
  "Flare",
  "Aqua",
  "Spike",
  "Shadow",
  "Breeze",
  "Blaze",
  "Luna",
  "Sunny",
  "Rumble",
  "Sparky",
  "Misty",
  "Rocky",
  "Frosty",
  "Whisper",
  "Glimmer",
  "Rusty",
  "Buddy",
  "Cinder",
  "Zephyr",
  "Nova",
  "Echo",
  "Fang",
  "Frost",
  "Pebble",
  "Specter",
  "Sapphire",
  "Dusty",
  "Ember",
  "Pebble",
  "Dusk",
  "Breezy",
  "Aurora",
  "Rusty",
  "Lunar",
  "Mystic",
  "Sparrow",
  "Thunder",
  "Blizzard",
  "Shadow",
  "Dawn",
  "Boulder",
  "Storm",
  "Whisper",
  "Smokey",
  "Crimson",
  "Buddy",
  "Glider",
  "Aurora",
]

 end
 
 