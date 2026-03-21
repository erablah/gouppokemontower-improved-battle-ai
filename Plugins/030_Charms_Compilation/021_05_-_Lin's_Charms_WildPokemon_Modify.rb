#===============================================================================
# * WildPokemon Modify
#===============================================================================

# Activates script when a wild pokemon is created
EventHandlers.add(:on_wild_pokemon_created, :charm_modify,
  proc { |pokemon|
    pbMaxIV(pokemon) if $player.activeCharm?(:GENECHARM)
    pbHiddenAbility(pokemon) if $player.activeCharm?(:HIDDENCHARM)
    pbEggMove(pokemon) if $player.activeCharm?(:HERITAGECHARM)
    pokemon.calc_stats
  }
)