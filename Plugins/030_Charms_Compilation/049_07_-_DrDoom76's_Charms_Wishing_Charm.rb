#===============================================================================
# * Wishing Charm
#===============================================================================
# Hotfix for compatibility with Bag Screen w/int. Party
if PluginManager.installed?("Bag Screen w/int. Party")
  class PokemonBag_Scene
	def pbRefreshParty
	  pbHardRefresh
      for i in 0...Settings::MAX_PARTY_SIZE
        if @party[i]
           @sprites["pokemon#{i}"].pokemon = @party[i]
        else
        end
      end
    end
  end
end

# Every day, awards player with one random item or Pokemon. Pokemon can be selected
#	auto from the auto setting, or from an approved list. Both settings are found in the Settings
#	file. Auto will generate a random Pokemon that isn't a Legendary or a starter. (Can be changed
#	here, that's just my personal preference. Approved list is also found in the settings file.
# Add or remove Pokemon from the approved list to have it randomly give just the Pokemon from the list.

# If WISHING_CHARM_USE_AUTO is set to true, it will automaticly generate the eggs from all possible species
# that aren't blacklisted.

def pbWishingStar
  $player.last_wish_time ||= 0
  current_time = Time.now
  time_difference = current_time - $player.last_wish_time
  seconds_passed = time_difference.to_i  # Convert to seconds
  hours_passed = seconds_passed / 3600  # 1 hour = 3600 seconds
  if hours_passed >= 24
    pbWishingCharmPoke
    $player.last_wish_time = current_time  # Update the last wish time
  else
    hours_remaining = 24 - hours_passed
    pbMessage(_INTL("You can make another wish in {1} hours.", hours_remaining))
  end
end

def pbWishingCharmPoke
  wishingCharmBoth       = DrCharmConfig::WISHING_CHARM_LIST_AND_POKE
  wishingCharmUseAuto    = DrCharmConfig::WISHING_CHARM_USE_AUTO
  # Wishing Charm setting for both items and Poke.
  if wishingCharmBoth
    # Chooses between items and Pokemon if true.
    if rand(100) < 50
      give_random_item
    else
      # If auto populate is true, runs the list from all species.
      if wishingCharmUseAuto
        wishingCharmAutoPop
      else
        # If false, pulls data from approved list.
        wishingCharmApprovedList
      end
    end
  else
    # If not items, jumps to just Pokemon. If use auto is on pulls auto.
    if wishingCharmUseAuto
      wishingCharmAutoPop
    else
      # Else pulls approved list.
      wishingCharmApprovedList
    end
  end
end
	
	
# Call to give random item
def give_random_item
  wishingCharmItems  = DrCharmConfig::WISHING_CHARM_ITEM_LIST
  if wishingCharmItems.empty?
    return "No approved items available."
  else
    random_item = wishingCharmItems.sample
    pbReceiveItem(random_item)
  end
end

# Call for auto population of the list.
def wishingCharmAutoPop
  pool = []
  autoUseBlacklist = DrCharmConfig::AUTO_USE_BLACKLIST
  blacklist = DrCharmConfig::WISHING_CHARM_BLACK_LIST
  noLegendary = DrCharmConfig::NO_LEGENDARY_AUTO
  wishingCharmLevel  = DrCharmConfig::WISHING_CHARM_PKMN_LEVEL
 #----Generate pool of possible Pokemon, no starters(blacklist), no legendaries---#
  GameData::Species.each do |species|
    species_id = species.id.to_sym
    pkmn = Pokemon.new(species,30)
    if noLegendary
#      next if species.flags.include?(:Legendary)
#      next if species.flags.include?(:Mythical)
#      next if species.flags.include?(:Paradox)
#      next if species.flags.include?(:UltraBeast)
      next if pkmn.species_data.has_flag?("Legendary")
      next if pkmn.species_data.has_flag?("Mythical")
      next if pkmn.species_data.has_flag?("Paradox")
      next if pkmn.species_data.has_flag?("UltraBeast")
    end
    if autoUseBlacklist
      next if blacklist.include?(species_id)
    end
    next unless species
    pool.push(species)
  end
  # Generate a Pokemon from the pool
  pkmn = pool.sample
  pbAddPokemon(pkmn, wishingCharmLevel)
end
	
# Generate pokemon from an approved list (settings file)	
def wishingCharmApprovedList
  wishingCharmLevel        = DrCharmConfig::WISHING_CHARM_PKMN_LEVEL
  wishingCharmApprovedList = DrCharmConfig::WISHING_CHARM_APPROVED_LIST
  pool = []
  # Generate a pool of approved Pokémon
  wishingCharmApprovedList.each do |species_id|
    species = GameData::Species.get(species_id)
    pool.push(species)
  end

  # Check if the approved list is not empty
  if pool.empty?
    pbMessage(_INTL("No approved Pokémon found."))
    return
  end

  pkmn = pool.sample
  pbAddPokemon(pkmn, wishingCharmLevel)
end