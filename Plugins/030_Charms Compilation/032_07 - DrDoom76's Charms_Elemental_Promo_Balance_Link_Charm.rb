#===============================================================================
# * Elemental Charms / Promo Charm / Balance Charm
#===============================================================================

class PokemonEncounters
  def choose_wild_pokemon(enc_type, chance_rolls = 1)
    if !enc_type || !GameData::EncounterType.exists?(enc_type)
      raise ArgumentError.new(_INTL("Encounter type {1} does not exist", enc_type))
    end
    enc_list = @encounter_tables[enc_type]
    return nil if !enc_list || enc_list.length == 0
    # Static/Magnet Pull prefer wild encounters of certain types, if possible.
    # If they activate, they remove all Pokémon from the encounter table that do
    # not have the type they favor. If none have that type, nothing is changed.
    first_pkmn = $player.first_pokemon
    if first_pkmn
      favored_type = nil
      case first_pkmn.ability_id
      when :FLASHFIRE
        favored_type = :FIRE if Settings::MORE_ABILITIES_AFFECT_WILD_ENCOUNTERS &&
                              GameData::Type.exists?(:FIRE) && rand(100) < 50
      when :HARVEST
        favored_type = :GRASS if Settings::MORE_ABILITIES_AFFECT_WILD_ENCOUNTERS &&
                               GameData::Type.exists?(:GRASS) && rand(100) < 50
      when :LIGHTNINGROD
        favored_type = :ELECTRIC if Settings::MORE_ABILITIES_AFFECT_WILD_ENCOUNTERS &&
                                GameData::Type.exists?(:ELECTRIC) && rand(100) < 50
      when :MAGNETPULL
        favored_type = :STEEL if GameData::Type.exists?(:STEEL) && rand(100) < 50
      when :STATIC
        favored_type = :ELECTRIC if GameData::Type.exists?(:ELECTRIC) && rand(100) < 50
      when :STORMDRAIN
        favored_type = :WATER if Settings::MORE_ABILITIES_AFFECT_WILD_ENCOUNTERS &&
                               GameData::Type.exists?(:WATER) && rand(100) < 50
      end

      if favored_type.nil?
        charm_list = $player.elementCharmList || []
        charms_active = $player.charmsActive || {}
        scaling_factor ||= 0 
        elementCharmEncounter = [DrCharmConfig::ELEMENTAL_CHARM_ENCOUNTER_RATE, 100].compact.min
        charm_list.each do |charm|
          if charms_active[charm] && Settings::MORE_ABILITIES_AFFECT_WILD_ENCOUNTERS
            type_effects = {
              :ELECTRICCHARM => :ELECTRIC,
              :FIRECHARM => :FIRE,
              :WATERCHARM => :WATER,
              :GRASSCHARM => :GRASS,
              :NORMALCHARM => :NORMAL,
              :FIGHTINGCHARM => :FIGHTING,
              :FLYINGCHARM => :FLYING,
              :POISONCHARM => :POISON,
              :GROUNDCHARM => :GROUND,
              :ROCKCHARM => :ROCK,
              :BUGCHARM => :BUG,
              :GHOSTCHARM => :GHOST,
              :STEELCHARM => :STEEL,
              :PSYCHICCHARM => :PSYCHIC,
              :ICECHARM => :ICE,
              :DRAGONCHARM => :DRAGON,
              :DARKCHARM => :DARK,
              :FAIRYCHARM => :FAIRY
            }
	    favored_type = type_effects[charm] if rand(100) < elementCharmEncounter
          end
        end
      end
      if favored_type
        new_enc_list = []
        enc_list.each do |enc|
          species_data = GameData::Species.get(enc[1])
          new_enc_list.push(enc) if species_data.types.include?(favored_type)
        end
        enc_list = new_enc_list if new_enc_list.length > 0
      end
    end
    # Link Charm increases Encounter Rate of Captured / KO'ed Pokemon and 
    ## Lowers Encounter Rate of Fled From Pokemon.
    if $player.activeCharm?(:LINKCHARM)
      new_enc_list = []
	  new_rate = 0
	  link_species = $player.link_charm_data[0]
	  link_chain = $player.link_charm_data[1]
	  fled_species = $player.link_charm_data[2].keys
	   enc_list.each do |enc|
	    enc_species = enc[1].to_sym
		if enc_species == link_species
		  new_rate = enc[0] + (link_chain * 10)
		  new_rate = [new_rate, 100].min
		  new_enc_list.push([new_rate, enc[1], enc[2], enc[3]])
		elsif fled_species.include?(enc_species)
		  species_chain = $player.link_charm_data[2][enc_species]
		  new_rate = enc[0] - (species_chain * 10)
		  new_rate = [new_rate, 0].max
		  new_enc_list.push([new_rate, enc[1], enc[2], enc[3]])
		else
		  new_enc_list.push(enc)
		end
	  end
	  enc_list = new_enc_list
    end
    # Balance charm makes probability of encounters the same for all species on map.
    if $player.activeCharm?(:BALANCECHARM)
      enc_list.each { |e| e[0] = 100/enc_list.length }
    end
    enc_list.sort! { |a, b| b[0] <=> a[0] }   # Highest probability first
    # Calculate the total probability value
    chance_total = 0
    enc_list.each { |a| chance_total += a[0] }
    # Choose a random entry in the encounter table based on entry probabilities
    rnd = 0
    chance_rolls.times do
      r = rand(chance_total)
      rnd = r if r > rnd   # Prefer rarer entries if rolling repeatedly
    end
    encounter = nil
    enc_list.each do |enc|
      rnd -= enc[0]
      next if rnd >= 0
      encounter = enc
      break
    end
	#Change
	if $player.activeCharm?(:LINKCHARM)
	  $player.link_charm_data[3] = encounter[1]
	end
	#End Change
    # Get the chosen species and level
    level = rand(encounter[2]..encounter[3])
    # Some abilities alter the level of the wild Pokémon
    if first_pkmn
      case first_pkmn.ability_id
      when :HUSTLE, :PRESSURE, :VITALSPIRIT
        level = encounter[3] if rand(100) < 50   # Highest possible level
      end
    end
    promoCharmEncounter = DrCharmConfig::PROMO_CHARM
    # Promo Charm increases the chance of encountering highest possible level on map. 30%
    level = encounter[3] if ($player.activeCharm?(:PROMOCHARM) && rand(100) < [promoCharmEncounter, 100].min)
  
    if Essentials::VERSION <= "20.9"
      # Black Flute and White Flute alter the level of the wild Pokémon
      if Settings::FLUTES_CHANGE_WILD_ENCOUNTER_LEVELS
        if $PokemonMap.blackFluteUsed
          level = [level + rand(1..4), GameData::GrowthRate.max_level].min
        elsif $PokemonMap.whiteFluteUsed
          level = [level - rand(1..4), 1].max
        end
      end
      # Return [species, level]
      return [encounter[1], level]
    else
      # Black Flute and White Flute alter the level of the wild Pokémon
      if $PokemonMap.lower_level_wild_pokemon
        level = [level - rand(1..4), 1].max
      elsif $PokemonMap.higher_level_wild_pokemon
        level = [level + rand(1..4), GameData::GrowthRate.max_level].min
      end
      # Return [species, level]
      return [encounter[1], level]
    end
  end
end