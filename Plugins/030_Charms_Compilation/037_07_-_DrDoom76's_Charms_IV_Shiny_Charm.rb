#===============================================================================
# * IV Charm
#===============================================================================

EventHandlers.add(:on_wild_pokemon_created, :charm_higher_IV, proc { |pkmn|
  ivCharmAddIv = DrCharmConfig::IV_CHARM_ADD_IV
  if $player.activeCharm?(:IVCHARM)
    pkmn.iv ||= {}
    GameData::Stat.each_main do |s|
      stat_id = s.id
      pkmn.iv[stat_id] = [pkmn.iv[stat_id] + ivCharmAddIv, 31].min if pkmn.iv[stat_id]
    end
  end
})

class DayCare
  module EggGenerator
  module_function

    def generate(mother, father)
      if mother.male? || father.female? || mother.genderless?
        mother, father = father, mother
      end
      mother_data = [mother, fluid_egg_group?(mother.species_data.egg_groups)]
      father_data = [father, fluid_egg_group?(father.species_data.egg_groups)]
      # Determine which parent the egg's species is based from
      species_parent = (mother_data[1]) ? father : mother
      # Determine the egg's species
      baby_species = determine_egg_species(species_parent.species, mother, father)
      mother_data.push(mother.species_data.breeding_can_produce?(baby_species))
      father_data.push(father.species_data.breeding_can_produce?(baby_species))
      # Generate egg
      egg = generate_basic_egg(baby_species)
      # Inherit properties from parent(s)
      inherit_form(egg, species_parent, mother_data, father_data)
      inherit_nature(egg, mother, father)
      inherit_ability(egg, mother_data, father_data)
      inherit_moves(egg, mother_data, father_data)
      inherit_IVs(egg, mother, father)
      inherit_poke_ball(egg, mother_data, father_data)
      # Calculate other properties of the egg
      set_shininess(egg, mother, father)   # Masuda method and Shiny Charm
      set_pokerus(egg)
      adjust_ivs(egg)
      # Recalculate egg's stats
      egg.calc_stats
      return egg
    end

    def adjust_ivs(egg)
      ivCharmIvEggAdd = DrCharmConfig::IVCHARM_IV_EGG_ADD
      if activeCharm?(:IVCHARM)
        egg.iv ||= {}
        GameData::Stat.each_main do |s|
          stat_id = s.id
          egg.iv[stat_id] = [egg.iv[stat_id] + ivCharmIvEggAdd, 31].min if egg.iv[stat_id]
        end
      end
    end
  
    def fluid_egg_group?(groups)
      return groups.include?(:Ditto) || groups.include?(:Ancestor)
    end

    def legendary_egg_group?(groups)
      egg_groups = egg_group_hash
      return egg_groups[groups[0]] > 13 || (groups[1] && egg_groups[groups[1]] > 13)
    end

    def set_shininess(egg, mother, father)
      # Start Settings #
      fatherMotherShiny = DrCharmConfig::FATHERMOTHER_SHINY
      motherFatherEggShinyChance = DrCharmConfig::MOTHERFATHER_EGG_SHINY_CHANCE
      shinyCharmShinyRetryEgg = DrCharmConfig::SHINYCHARM_SHINY_RETRY_EGG
      # End Settings #
      shiny_retries = 0
      if father.owner.language != mother.owner.language
        shiny_retries += (Settings::MECHANICS_GENERATION >= 8) ? 6 : 5
      end
      if fatherMotherShiny
	# I added in 3 extra retries (chances) if mother / father are shiny as well.
        shiny_retries += motherFatherEggShinyChance if father.shiny? || mother.shiny?
      end
      # Gives 2 extra retries(chances) with Shiny Charm.
      shiny_retries += shinyCharmShinyRetryEgg if $player.activeCharm?(:SHINYCHARM)
      return if shiny_retries == 0
      shiny_retries.times do
        break if egg.shiny?
        egg.shiny = nil   # Make it recalculate shininess
        egg.personalID = rand(2**16) | (rand(2**16) << 16)
      end
    end
  end
end