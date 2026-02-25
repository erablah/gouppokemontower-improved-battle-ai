#===============================================================================
# * Link Charm
#===============================================================================

# Sets Link Charm Data on Capture / KO , Fled.
EventHandlers.add(:on_wild_battle_end, :twin_charm_tracker,
  proc { |species, level, decision|
    if activeCharm?(:LINKCHARM)
	  #Change added in case species changes due to outside factor and doesn't match a species within the
	  # enc_list. I.E. Plugin: Automatic Level Scaling - Automaticly evolves wild pokemon.
	  if species != $player.link_charm_data[3]
	    species = $player.link_charm_data[3]
	  end
	  #End Change
      if [1, 4].include?(decision) # Defeated/caught
        if $player.link_charm_data[0] != species
          $player.link_charm_data[1] = 0 # Reset chain count to 0
        end
        $player.link_charm_data[0] = species
        $player.link_charm_data[1] += 1
      elsif [0, 3].include?(decision) # Draw/Flee
        $player.link_charm_data[2] ||= {} # Use a hash to store species and their flee counts
        if $player.link_charm_data[2].key?(species)
          $player.link_charm_data[2][species] += 1
        else
          # Stores species and chain count for species
          $player.link_charm_data[2][species] = 1
        end
      else
	    # Species, Chain Count, **Fled Species / Chain Count ** Added nil for automatic evolving pokemon
        $player.link_charm_data = [0, 0, {}, nil]
      end
    end
  }
)

# Resets Link Charm Data on entering map.
EventHandlers.add(:on_enter_map, :clear_link_charm,
  proc { |_old_map_id|
    if $player.activeCharm?(:LINKCHARM)
      $player.link_charm_data ||= [0, 0, [], nil] #Species, Chain Count, Fled Species/Chain Count
    end
  }
)

# Allows chance that Chained Pokemon will have perfect IVs. Starts after Chain Count is 5.
EventHandlers.add(:on_wild_pokemon_created, :link_charm_perfect_iv,
  proc { |pkmn|
    if $player.activeCharm?(:LINKCHARM) && DrCharmConfig::LC_PERFECT_IV  && pkmn.species == $player.link_charm_data[0]
      base_chance = DrCharmConfig::LC_IV_CHANCE
      link_chain = $player.link_charm_data[1]
      iv_chance = link_chain > DrCharmConfig::LC_CHAIN_COUNT_IV ? (link_chain - DrCharmConfig::LC_CHAIN_COUNT_IV) : 0
      while iv_chance > 0
        if rand(65_536) < base_chance
          pkmn.iv[:HP] = 31
          pkmn.iv[:ATTACK] = 31
          pkmn.iv[:DEFENSE] = 31
          pkmn.iv[:SPECIAL_ATTACK] = 31
          pkmn.iv[:SPECIAL_DEFENSE] = 31
          pkmn.iv[:SPEED] = 31
          pkmn.calc_stats
          break
        end
      end
    end
  }
)