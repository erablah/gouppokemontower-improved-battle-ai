#===============================================================================
# * Roaming Charm
#===============================================================================

# Adds an extra 25% chance of encountering Roaming Pokemon
EventHandlers.add(:on_wild_species_chosen, :roaming_pokemon,
  proc { |encounter|
    $game_temp.roamer_index_for_encounter = nil
    next if !encounter
    # Give the regular encounter if encountering a roaming Pokémon isn't possible
    next if $PokemonGlobal.roamedAlready
    next if $PokemonGlobal.partner
    next if $game_temp.poke_radar_data
    if $player.activeCharm?(:ROAMINGCHARM)
		next if rand(100) < (75 - DrCharmConfig::ROAMING_CHARM_CHANCE) # (25(%) - setting)
    else
		next if rand(100) < 75   # 25% chance of encountering a roaming Pokémon
    end
    # Look at each roaming Pokémon in turn and decide whether it's possible to
    # encounter it
    currentRegion = pbGetCurrentRegion
    currentMapName = $game_map.name
    possible_roamers = []
    Settings::ROAMING_SPECIES.each_with_index do |data, i|
      # data = [species, level, Game Switch, roamer method, battle BGM, area maps hash]
      next if !GameData::Species.exists?(data[0])
      next if data[2] > 0 && !$game_switches[data[2]]   # Isn't roaming
      next if $PokemonGlobal.roamPokemon[i] == true   # Roaming Pokémon has been caught
      # Get the roamer's current map
      roamerMap = $PokemonGlobal.roamPosition[i]
      if !roamerMap
        mapIDs = pbRoamingAreas(i).keys   # Hash of area patrolled by the roaming Pokémon
        next if !mapIDs || mapIDs.length == 0   # No roaming area defined somehow
        roamerMap = mapIDs[rand(mapIDs.length)]
        $PokemonGlobal.roamPosition[i] = roamerMap
      end
      # If roamer isn't on the current map, check if it's on a map with the same
      # name and in the same region
      if roamerMap != $game_map.map_id
        map_metadata = GameData::MapMetadata.try_get(roamerMap)
        next if !map_metadata || !map_metadata.town_map_position ||
                map_metadata.town_map_position[0] != currentRegion
        next if pbGetMapNameFromId(roamerMap) != currentMapName
      end
      # Check whether the roamer's roamer method is currently possible
      next if !pbRoamingMethodAllowed(data[3])
      # Add this roaming Pokémon to the list of possible roaming Pokémon to encounter
      possible_roamers.push([i, data[0], data[1], data[4]])   # [i, species, level, BGM]
    end
    # No encounterable roaming Pokémon were found, just have the regular encounter
    next if possible_roamers.length == 0
    # Pick a roaming Pokémon to encounter out of those available
    roamer = possible_roamers.sample
    $PokemonGlobal.roamEncounter = roamer
    $game_temp.roamer_index_for_encounter = roamer[0]
    $PokemonGlobal.nextBattleBGM = roamer[3] if roamer[3] && !roamer[3].empty?
    $game_temp.force_single_battle = true
    encounter[0] = roamer[1]   # Species
    encounter[1] = roamer[2]   # Level
  }
)