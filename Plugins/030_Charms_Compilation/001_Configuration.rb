#===============================================================================
# * Charm Configuration
#===============================================================================

module CharmConfig
  # Set to true if you want to activate and disable the charms.
  ACTIVE_CHARM = true
end

module LinCharmConfig
  #=======Gene Charm=======#
  # Sets the percentage for max IV. Default: 10 (of 100)
  MAX_IV_PERC = 10

  #=======Hidden Charm=======#
  # Sets the percentage for hidden ability. Default: 10 (of 100)
  HIDDEN_ABILITY_PERC = 10

  #=======Heritage Charm=======#
  # Sets the percentage for egg moves. Default: 10 (of 100)
  EGG_MOVE_PERC = 10

  # Max number of egg moves wild pokémon can appear as. Range of 0 (none) and 4 (all).
  EGG_MOVE = 1

  #=======Easy & Hard Charm=======#
  # The amount of levels to increase or reduce for wild and trainer pokemon. Negative numbers reduce the level.
  EASY_LEVEL = -5
  HARD_LEVEL = 5

  # Set to true to take away 1 pokemon from trainers when on easy or normal if they have more than 1 pokemon.
  # Be aware that if you activate this configuration, the full teams in the trainer PBS will be used only when
  # the Hard Charm is active.
  EXTRA_POKEMON = true

  # The position of the deleted pokemon from the last position. 0 deletes the last pokemon, 1 deletes the one
  # before the last pokemon and so on.
  POKEMON_POSITION = 1
end