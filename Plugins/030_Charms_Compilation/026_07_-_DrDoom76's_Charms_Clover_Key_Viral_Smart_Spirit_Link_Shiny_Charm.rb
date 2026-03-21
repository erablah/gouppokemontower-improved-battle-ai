#===============================================================================
# * Clover Charm / Key Charm / Viral Charm / Smart Charm / Spirit Charm
#===============================================================================

def pbGenerateWildPokemon(species, level, isRoamer = false)
  genwildpoke = Pokemon.new(species, level)
  # Give the wild Pokémon a held item
  items = genwildpoke.wildHoldItems
  first_pkmn = $player.first_pokemon
  chances = [50, 5, 1]

   # Settings start
  charmCommon = [DrCharmConfig::CLOVERCOMMON, 100].min
  charmUncommon = [DrCharmConfig::CLOVERUNCOMMON, 100].min
  charmRare = [DrCharmConfig::CLOVERRARE, 100].min
  charmCombineCommon = [DrCharmConfig::COMBINEDCOMMON, 100].min
  charmCombineUncommon = [DrCharmConfig::COMBINEDUNCOMMON, 100].min
  charmCombineRare = [DrCharmConfig::COMBINEDRARE, 100].min
  shinyCharmPokeRetry = DrCharmConfig::SHINY_CHANCE_RETRIES
  lureCharmShiny = DrCharmConfig::LURE_CHARM_RETRIES
  shinyRetriesLinkCharm = DrCharmConfig::CHAIN_INCREASE_SHINY
  smartCharmEggTutorMove = [DrCharmConfig::SMARTCHARM_EGGTUTOR_MOVE, 100].min
  viralCharmPokeRus = [DrCharmConfig::VIRAL_CHARM_POKERUS, 100].min
  keyCharmHA = [DrCharmConfig::KEYCHARM_HIDDEN_ABILITY, 100].min
  # End Settings

  if first_pkmn
    case first_pkmn.ability_id
    when :COMPOUNDEYES
      chances = [60, 20, 5]
    when :SUPERLUCK
      chances = [60, 20, 5] if Settings::MORE_ABILITIES_AFFECT_WILD_ENCOUNTERS
    end
    if $player.activeCharm?(:CLOVERCHARM)
      chances = [charmCommon, charmUncommon, charmRare]
    elsif $player.activeCharm?(:CLOVERCHARM) && (first_pkmn.ability_id == :COMPOUNDEYES || first_pkmn.ability_id == :SUPERLUCK)
      chances = [charmCombineCommon, charmCombineUncommon, charmCombineRare]
    end
  end
    
  itemrnd = rand(100)
  if (items[0] == items[1] && items[1] == items[2]) || itemrnd < chances[0]
    genwildpoke.item = items[0].sample
  elsif itemrnd < (chances[0] + chances[1])
    genwildpoke.item = items[1].sample
  elsif itemrnd < (chances[0] + chances[1] + chances[2])
    genwildpoke.item = items[2].sample
  end
  # Improve chances of shiny Pokémon with Shiny Charm and battling more of the
  # same species
  shiny_retries = 0
  shiny_retries += shinyCharmPokeRetry if $player.activeCharm?(:SHINYCHARM)
  shiny_retries += lureCharmShiny if $player.activeCharm?(:LURECHARM) && $PokemonGlobal.fishing
  # Link Charm - Adds one extra Shiny Retry per chain count
  if activeCharm?(:LINKCHARM)
    if genwildpoke.species == $player.link_charm_data[0] && shinyRetriesLinkCharm
      shiny_retries += ($player.link_charm_data[1] * 1)
    end
  end
  if Settings::HIGHER_SHINY_CHANCES_WITH_NUMBER_BATTLED
    values = [0, 0]
    case $player.pokedex.battled_count(species)
    when 0...50    then values = [0, 0]
    when 50...100  then values = [1, 15]
    when 100...200 then values = [2, 20]
    when 200...300 then values = [3, 25]
    when 300...500 then values = [4, 30]
    else                values = [5, 30]
    end
    shiny_retries += values[0] if values[1] > 0 && rand(1000) < values[1]
  end
  if shiny_retries > 0
    shiny_retries.times do
      break if genwildpoke.shiny?
      genwildpoke.shiny = nil   # Make it recalculate shininess
      genwildpoke.personalID = rand(2**16) | (rand(2**16) << 16)
    end
  end
  # Give Pokérus
  genwildpoke.givePokerus if rand(65_536) < Settings::POKERUS_CHANCE || ($player.activeCharm?(:VIRALCHARM) && rand(100) < viralCharmPokeRus)
  # Change wild Pokémon's gender/nature depending on the lead party Pokémon's
  # ability
  if first_pkmn
    if first_pkmn.hasAbility?(:CUTECHARM) && !genwildpoke.singleGendered?
      if first_pkmn.male?
        (rand(3) < 2) ? genwildpoke.makeFemale : genwildpoke.makeMale
      elsif first_pkmn.female?
        (rand(3) < 2) ? genwildpoke.makeMale : genwildpoke.makeFemale
      end
    elsif first_pkmn.hasAbility?(:SYNCHRONIZE) || $player.activeCharm?(:SPIRITCHARM)
      if !isRoamer && (Settings::MORE_ABILITIES_AFFECT_WILD_ENCOUNTERS || (rand(100) < 50))
        genwildpoke.nature = first_pkmn.nature
      end
    end
  end
  if ($player.activeCharm?(:SMARTCHARM) && rand(100) < smartCharmEggTutorMove)
    specialmoves = genwildpoke.species_data.tutor_moves + genwildpoke.species_data.get_egg_moves
    genwildpoke.learn_move(specialmoves.sample)
  end
  if ($player.activeCharm?(:SMARTCHARM) && rand(100) < smartCharmEggTutorMove)
    specialmoves = genwildpoke.species_data.tutor_moves + genwildpoke.species_data.get_egg_moves
    genwildpoke.learn_move(specialmoves.sample)
  end
  if DrCharmConfig::USE_ALL_HA
    # Key Charm has 30% chance of Wild Pokemon having their Hidden Ability.
    if $player.activeCharm?(:KEYCHARM) && rand(100) < keyCharmHA
	  abilities = genwildpoke.getAbilityList
	  # This will pull out all higher than and equal to 2 (Hidden Abilities)
	  filtered_abilities = abilities.select { |ability| ability[1] >= 2 }
	  numbers_only = filtered_abilities.map { |ability| ability[1] }
	  # Will check to make sure numbers_only(HA) has numbers, if so, will give one of them, randomly selected.
	  if numbers_only.any?
	    random_ability_index = numbers_only.sample   
	    genwildpoke.ability_index = random_ability_index 
	  end
	end  
  else
    genwildpoke.ability_index = 2 if ($player.activeCharm?(:KEYCHARM) && rand(100) < keyCharmHA)
  end
  # Trigger events that may alter the generated Pokémon further
  EventHandlers.trigger(:on_wild_pokemon_created, genwildpoke)
  return genwildpoke
end