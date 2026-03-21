#===============================================================================
# * Color Charm
#===============================================================================

# Doubles the base chance that a Pokemon will appear with a different Color Variant.
# Default in the Pokemon Color Variant is 256 / 65536.
# Essentially adds a second "roll" to get a Pokemon with a Hue.
# Set hue value to wild pokemon
if PluginManager.installed?("Pokemon Color Variants")
  EventHandlers.add(:on_wild_pokemon_created,:pokemon_color_variants2,
    proc { |pokemon|
      if $player.activeCharm?(:COLORCHARM) && pokemon.hue == 0
        if PokemonColorVariants::HUE_POKEMON_CHANCE > rand(65536)
          if PokemonColorVariants::SPECIFIC_HUE_ONLY && PokemonColorVariants::POKEMON_HUE.include?(pokemon.species)
            hue = PokemonColorVariants::POKEMON_HUE[pokemon.species]
            pokemon.hue = hue[rand(hue.length)] % 360
          else
            pokemon.hue = rand(360)
          end
          pokemon.hue = 0 if PokemonColorVariants::SHINY_ONLY && !pokemon.shiny?
          pokemon.hue = 0 if PokemonColorVariants::SUPER_SHINY_ONLY && !pokemon.super_shiny?
        end
      end
    }
  )
end