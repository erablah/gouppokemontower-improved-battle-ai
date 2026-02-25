#===============================================================================
# * Catching Charm / Elemental Charm
#===============================================================================

module Battle::CatchAndStoreMixin
  #=============================================================================
  # Calculate how many shakes a thrown Poké Ball will make (4 = capture)
  #=============================================================================
  def pbCaptureCalc(pkmn, battler, catch_rate, ball)
    return 4 if $DEBUG && Input.press?(Input::CTRL)
    # Get a catch rate if one wasn't provided
    catch_rate = pkmn.species_data.catch_rate if !catch_rate
    # Modify catch_rate depending on the Poké Ball's effect
    if !pkmn.species_data.has_flag?("UltraBeast") || ball == :BEASTBALL
      catch_rate = Battle::PokeBallEffects.modifyCatchRate(ball, catch_rate, self, battler)
    else
      catch_rate /= 10
    end
    #Added in Elemental Charm effecting capture rate
    elemental_charm_type = nil
    charm_list = [
      :BUGCHARM, :DARKCHARM, :DRAGONCHARM, :ELECTRICCHARM, :FAIRYCHARM, :FIGHTINGCHARM,
      :FIRECHARM, :FLYINGCHARM, :GHOSTCHARM, :GRASSCHARM, :GROUNDCHARM, :ICECHARM,
      :NORMALCHARM, :PSYCHICCHARM, :POISONCHARM, :ROCKCHARM, :STEELCHARM, :WATERCHARM
    ]
    charms_active = $player.charmsActive || {}
    charm_list.each do |charm|
      if charms_active[charm]
        type_effects = {
          :ELECTRICCHARM => :ELECTRIC,
          :FIRECHARM 	 => :FIRE,
          :WATERCHARM 	 => :WATER,
          :GRASSCHARM 	 => :GRASS,
          :NORMALCHARM 	 => :NORMAL,
          :FIGHTINGCHARM => :FIGHTING,
          :FLYINGCHARM	 => :FLYING,
          :POISONCHARM 	 => :POISON,
          :GROUNDCHARM 	 => :GROUND,
          :ROCKCHARM 	 => :ROCK,
          :BUGCHARM 	 => :BUG,
          :GHOSTCHARM 	 => :GHOST,
          :STEELCHARM 	 => :STEEL,
          :PSYCHICCHARM  => :PSYCHIC,
          :ICECHARM 	 => :ICE,
          :DRAGONCHARM 	 => :DRAGON,
          :DARKCHARM 	 => :DARK,
          :FAIRYCHARM	 => :FAIRY
        }
        elemental_charm_type = type_effects[charm]
        break if elemental_charm_type
      end
    end
    # First half of the shakes calculation
    a = battler.totalhp
    b = battler.hp
    x = (((3 * a) - (2 * b)) * catch_rate.to_f) / (3 * a)
    # Calculation modifiers
    if battler.status == :SLEEP || battler.status == :FROZEN
      x *= 2.5
    elsif battler.status != :NONE
      x *= 1.5
    end
    if elemental_charm_type
      type_modifier = DrCharmConfig::ELEMENTAL_CHARM_CAPTURE_MODIFIER
      if pkmn.hasType?(elemental_charm_type)
        x *= type_modifier
      end
    end
    x = x.floor
    x = 1 if x < 1
    # Definite capture, no need to perform randomness checks
    return 4 if x >= 255 || Battle::PokeBallEffects.isUnconditional?(ball, self, battler)
    # Second half of the shakes calculation
    y = (65_536 / ((255.0 / x)**0.1875)).floor
    # Critical capture check
    if Settings::ENABLE_CRITICAL_CAPTURES
      dex_modifier = 0
      numOwned = $player.pokedex.owned_count
      if numOwned > 600
        dex_modifier = 5
      elsif numOwned > 450
        dex_modifier = 4
      elsif numOwned > 300
        dex_modifier = 3
      elsif numOwned > 150
        dex_modifier = 2
      elsif numOwned > 30
        dex_modifier = 1
      end
	  # Catching Charm increases chance of Critical Capture.(Guaranteed capture)
      dex_modifier *= DrCharmConfig::CATCHING_CHARM_CRIT if $player.activeCharm?(:CATCHINGCHARM)
      c = x * dex_modifier / 12
      # Calculate the number of shakes
      if c > 0 && pbRandom(256) < c
        @criticalCapture = true
        return 4 if pbRandom(65_536) < y
        return 0
      end
    end
    # Calculate the number of shakes
    numShakes = 0
    4.times do |i|
      break if numShakes < i
      numShakes += 1 if pbRandom(65_536) < y
    end
    return numShakes
  end
end