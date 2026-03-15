#===============================================================================
# Battle::AI::AIMove — predicted_damage, field/transform simulation, multi-hit
#===============================================================================

class Battle::AI::AIMove
  PRIMAL_WEATHERS = [:HarshSun, :HeavyRain, :StrongWinds].freeze

  alias rough_damage_original rough_damage

  def rough_damage
    case self.rough_type
    when :WATER then return 1 if @ai.battle.pbWeather == :HarshSun
    when :FIRE  then return 1 if @ai.battle.pbWeather == :HeavyRain
    end
    # Tera Blast / Tera Starstorm: set category based on higher offensive stat
    if ["CategoryDependsOnHigherDamageTera",
        "TerapagosCategoryDependsOnHigherDamage"].include?(function_code)
      user_battler = @ai.user.battler
      realAtk, realSpAtk = user_battler.getOffensiveStats
      @move.instance_variable_set(:@calcCategory, (realAtk > realSpAtk) ? 0 : 1)
    end
    return rough_damage_original
  end

  def simulated_field_weather(switch_in_pkmn, current)
    return current unless switch_in_pkmn
    new_w = current
    if switch_in_pkmn.isSpecies?(:KYOGRE) && switch_in_pkmn.hasItem?(:BLUEORB)
      new_w = :HeavyRain
    elsif switch_in_pkmn.isSpecies?(:GROUDON) && switch_in_pkmn.hasItem?(:REDORB)
      new_w = :HarshSun
    else
      new_w = case switch_in_pkmn.ability_id
      when :DROUGHT, :ORICHALCUMPULSE then :Sun
      when :DRIZZLE                   then :Rain
      when :SANDSTREAM                then :Sandstorm
      when :SNOWWARNING               then :Hail
      when :DESOLATELAND              then :HarshSun
      when :PRIMORDIALSEA             then :HeavyRain
      when :DELTASTREAM               then :StrongWinds
      else return current
      end
    end
    # StrongWinds cannot be replaced by HarshSun or HeavyRain
    return current if current == :StrongWinds && new_w != :StrongWinds
    # Primal weather can only be replaced by another primal weather
    return current if PRIMAL_WEATHERS.include?(current) && !PRIMAL_WEATHERS.include?(new_w)
    return new_w
  end

  def simulated_field_terrain(switch_in_pkmn, current)
    return current unless switch_in_pkmn
    case switch_in_pkmn.ability_id
    when :ELECTRICSURGE, :HADRONENGINE then :Electric
    when :GRASSYSURGE                  then :Grassy
    when :MISTYSURGE                   then :Misty
    when :PSYCHICSURGE                 then :Psychic
    else current
    end
  end

  #---------------------------------------------------------------------------
  # Terastallization pre-evaluation: evaluate once per turn and cache
  #---------------------------------------------------------------------------
  def should_simulate_tera?(idx, real_ai_user_idx = nil)
    ai_user_idx = real_ai_user_idx || @ai.user.index
    return false unless idx == ai_user_idx
    return false unless @ai.battle.respond_to?(:pbCanTerastallize?)
    return false unless @ai.battle.pbCanTerastallize?(idx)
    return false if @ai.battle.battlers[idx]&.tera?
    key = [ai_user_idx, @ai.battle.turnCount]
    @ai.instance_variable_set(:@_tera_cache, {}) unless @ai.instance_variable_get(:@_tera_cache)
    cache = @ai.instance_variable_get(:@_tera_cache)
    return cache[key] if cache.key?(key)
    cache[key] = @ai.pbEnemyShouldTerastallize?
  end

  #---------------------------------------------------------------------------
  # Mega Evolution / Terastallization simulation (AI's own battler only)
  #---------------------------------------------------------------------------
  def maybe_simulate_transform(battler, idx, override_pokemon, real_ai_user_idx = nil)
    sim = { mega: false, tera: false }
    return sim if override_pokemon  # Skip in hypothetical matchups (ScoreReplacement)

    # Mega Evolution: already registered (decided before move scoring)
    if @ai.battle.pbRegisteredMegaEvolution?(idx) && !battler.mega?
      sim[:prev_form] = battler.form
      battler.pokemon.makeMega
      battler.form = battler.pokemon.form
      battler.pbUpdate(true)
      sim[:mega] = true
      PBDebug.log_ai("[predicted_damage] Mega Evolution simulation applied: #{battler.name} (idx=#{idx})")
      return sim  # Cannot Mega + Tera simultaneously
    end

    # Terastallization: use cached pre-evaluation
    if should_simulate_tera?(idx, real_ai_user_idx)
      sim[:prev_tera] = battler.pokemon.instance_variable_get(:@terastallized)
      sim[:prev_form] = battler.form
      battler.pokemon.instance_variable_set(:@terastallized, true)
      # form_update includes scene calls, so only use pbUpdate(true)
      if battler.form != battler.pokemon.form
        battler.form = battler.pokemon.form
      end
      battler.pbUpdate(true)
      sim[:tera] = true
      PBDebug.log_ai("[predicted_damage] Terastallization simulation applied: #{battler.name} (idx=#{idx}, type=#{battler.pokemon.tera_type})")
    end

    sim
  end

  #---------------------------------------------------------------------------
  # Restore simulation state
  #---------------------------------------------------------------------------
  def restore_transform(battler, sim)
    if sim[:mega]
      battler.pokemon.makeUnmega
      battler.form = sim[:prev_form]
      battler.pbUpdate(true)
    end
    if sim[:tera]
      battler.pokemon.instance_variable_set(:@terastallized, sim[:prev_tera])
      battler.form = sim[:prev_form]
      battler.pbUpdate(true)
    end
  end

  #---------------------------------------------------------------------------
  # Tera STAB correction: compensate for the difference between rough_damage's
  # simple STAB and the actual Tera STAB multiplier.
  # rough_damage applies 1.5x/2.0x(Adaptability) based on pbTypes, but
  # Terastallization requires different multipliers depending on the
  # original type + Tera type combination.
  #---------------------------------------------------------------------------
  def tera_stab_correction(user_battler, calc_type)
    return 1.0 unless user_battler.tera?
    return 1.0 unless calc_type

    adaptability = user_battler.hasActiveAbility?(:ADAPTABILITY)
    # Stellar type ignores Adaptability
    adaptability = false if user_battler.tera_type == :STELLAR

    pre_types = user_battler.pbPreTeraTypes
    is_original = pre_types.include?(calc_type)
    is_tera_boosted = user_battler.typeTeraBoosted?(calc_type)

    # Value applied by rough_damage (based on pbTypes override)
    current_types = user_battler.pbTypes(true)
    if current_types.include?(calc_type)
      applied = adaptability ? 2.0 : 1.5
    else
      applied = 1.0
    end

    # The actual Tera STAB value that should be applied
    if is_original && is_tera_boosted
      correct = adaptability ? 2.25 : 2.0
    elsif is_original
      correct = adaptability ? 2.0 : 1.5
    elsif is_tera_boosted
      stab = (user_battler.tera_type == :STELLAR) ? 1.2 : 1.5
      correct = adaptability ? 2.0 : stab
    else
      correct = 1.0
    end

    return correct / applied
  end

  #---------------------------------------------------------------------------
  # Simulation setup: swap battlers, apply Intimidate, field, Mega/Tera
  # Returns a state hash used by restore_simulation to undo everything.
  #---------------------------------------------------------------------------
  def setup_simulation(user, target, user_pokemon, target_pokemon)
    sim = {}
    user_idx   = user.index
    target_idx = target.index

    # Save AI user/target references
    sim[:prev_user]   = @ai.user
    sim[:prev_target] = @ai.target
    sim[:user]        = user
    sim[:target]      = target
    sim[:user_idx]    = user_idx
    sim[:target_idx]  = target_idx

    # Swap battler slots for hypothetical matchups
    if user_pokemon
      sim[:prev_user_battler] = @ai.battle.battlers[user_idx]
      temp = Battle::Battler.new(@ai.battle, user_idx)
      temp.pbInitialize(user_pokemon, 0)
      @ai.battle.battlers[user_idx] = temp
    end
    if target_pokemon
      sim[:prev_target_battler] = @ai.battle.battlers[target_idx]
      temp = Battle::Battler.new(@ai.battle, target_idx)
      temp.pbInitialize(target_pokemon, 0)
      @ai.battle.battlers[target_idx] = temp
    end

    @ai.instance_variable_set(:@user, user)
    @ai.instance_variable_set(:@target, target)
    user.refresh_battler
    target.refresh_battler

    # Simulate Intimidate
    sim[:intimidate] = simulate_intimidate(user_idx, target_idx, user_pokemon, target_pokemon)

    # Mega Evolution / Terastallization simulation
    # Pass the original AI user index so Tera simulation works for both
    # offensive (attacker) and defensive (defender) damage calculations.
    real_ai_user_idx = sim[:prev_user].index
    sim[:eff_user]   = @ai.battle.battlers[user_idx]
    sim[:eff_target] = @ai.battle.battlers[target_idx]
    sim[:user_sim]   = maybe_simulate_transform(sim[:eff_user], user_idx, user_pokemon, real_ai_user_idx)
    sim[:target_sim] = maybe_simulate_transform(sim[:eff_target], target_idx, target_pokemon, real_ai_user_idx)

    # Field weather/terrain override
    switch_in_pkmn = user_pokemon || target_pokemon
    sim[:orig_weather] = @ai.battle.field.weather
    sim[:orig_terrain] = @ai.battle.field.terrain
    @ai.battle.field.instance_variable_set(:@weather, simulated_field_weather(switch_in_pkmn, sim[:orig_weather]))
    @ai.battle.field.instance_variable_set(:@terrain, simulated_field_terrain(switch_in_pkmn, sim[:orig_terrain]))

    sim
  end

  #---------------------------------------------------------------------------
  # Simulate Intimidate: if the switch-in candidate has Intimidate,
  # temporarily lower the opposing battler's Attack by 1 stage.
  #---------------------------------------------------------------------------
  INTIMIDATE_IMMUNE = [:CLEARBODY, :WHITESMOKE, :FULLMETALBODY,
                       :HYPERCUTTER, :INNERFOCUS, :OBLIVIOUS,
                       :OWNTEMPO, :SCRAPPY, :GUARDDOG].freeze

  def simulate_intimidate(user_idx, target_idx, user_pokemon, target_pokemon)
    if target_pokemon && target_pokemon.ability_id == :INTIMIDATE
      return try_intimidate_battler(@ai.battle.battlers[user_idx])
    elsif user_pokemon && user_pokemon.ability_id == :INTIMIDATE
      return try_intimidate_battler(@ai.battle.battlers[target_idx])
    end
    nil
  end

  def try_intimidate_battler(battler)
    return nil unless battler
    return nil if battler.hasActiveAbility?(INTIMIDATE_IMMUNE) || @ai.battle.moldBreaker
    orig_stage = battler.stages[:ATTACK]
    new_stage = [orig_stage - 1, -6].max
    return nil if new_stage == orig_stage
    battler.stages[:ATTACK] = new_stage
    { battler: battler, orig_stage: orig_stage }
  end

  #---------------------------------------------------------------------------
  # Restore all simulation state
  #---------------------------------------------------------------------------
  def restore_simulation(sim)
    return unless sim
    # Restore Intimidate
    if sim[:intimidate]
      sim[:intimidate][:battler].stages[:ATTACK] = sim[:intimidate][:orig_stage]
    end
    # Restore field
    @ai.battle.field.instance_variable_set(:@weather, sim[:orig_weather])
    @ai.battle.field.instance_variable_set(:@terrain, sim[:orig_terrain])
    # Restore battler slots
    @ai.battle.battlers[sim[:user_idx]]   = sim[:prev_user_battler]   if sim[:prev_user_battler]
    @ai.battle.battlers[sim[:target_idx]] = sim[:prev_target_battler] if sim[:prev_target_battler]
    # Restore transforms
    restore_transform(sim[:eff_user], sim[:user_sim]) if sim[:user_sim]
    restore_transform(sim[:eff_target], sim[:target_sim]) if sim[:target_sim]
    # Restore AI references
    @ai.instance_variable_set(:@user, sim[:prev_user])
    @ai.instance_variable_set(:@target, sim[:prev_target])
    sim[:user].refresh_battler
    sim[:target].refresh_battler
    sim[:prev_user]&.refresh_battler
    sim[:prev_target]&.refresh_battler
  end

  #---------------------------------------------------------------------------
  # Check if the move is blocked by immunities (returns dmg if immune)
  #---------------------------------------------------------------------------
  def check_immunities(dmg, calc_type, eff_user, eff_target)
    # Psychic Terrain blocks priority moves from hitting grounded targets
    if @move.priority > 0 && @ai.battle.field.terrain == :Psychic &&
       eff_target.affectedByTerrain?
      return dmg
    end
    # Ground immunity: airborne? covers Flying, Levitate, Air Balloon, Gravity,
    # and on live battlers also MagnetRise, Telekinesis, SmackDown, Ingrain.
    if calc_type == :GROUND && eff_target.airborne? && !@move.hitsFlyingTargets?
      return dmg
    end
    # MoveImmunity abilities: Flash Fire, Volt Absorb, Water Absorb, Dry Skin,
    # Lightning Rod, Motor Drive, Storm Drain, Sap Sipper, Soundproof, Bulletproof,
    # Wonder Guard, Good as Gold, Wind Rider, Well-Baked Body, Earth Eater, etc.
    if eff_target.abilityActive? && !@ai.battle.moldBreaker
      if Battle::AbilityEffects.triggerMoveImmunity(
           eff_target.ability, eff_user, eff_target,
           @move, calc_type, @ai.battle, false)
        return dmg
      end
    end

    # Disguise (Mimikyu): first damaging hit is nullified while in disguised form
    hit_count = expected_multi_hits(eff_user)
    if eff_target.abilityActive? && !@ai.battle.moldBreaker &&
       eff_target.ability_id == :DISGUISE && eff_target.form == 0
      return dmg.to_f/hit_count - eff_target.hp.to_f/8
    end
    # Ice Face (Eiscue): first physical hit is nullified while in Ice Face form
    if eff_target.abilityActive? && !@ai.battle.moldBreaker &&
       eff_target.ability_id == :ICEFACE && eff_target.form == 0 &&
       @move.physicalMove?
      return dmg/hit_count
    end
    return 0
  end

  #---------------------------------------------------------------------------
  # Apply Tera STAB damage corrections
  #---------------------------------------------------------------------------
  def apply_damage_corrections(dmg, eff_user, user_sim, calc_type)
    # Tera STAB correction (only when attacker is Tera-simulated)
    if user_sim[:tera]
      correction = tera_stab_correction(eff_user, calc_type)
      if correction != 1.0
        PBDebug.log_ai("[predicted_damage] Tera STAB correction: #{correction.round(3)}x (#{calc_type})")
        dmg = (dmg * correction).round
      end
    end
    dmg
  end

  #---------------------------------------------------------------------------
  # predicted_damage: orchestrator
  #---------------------------------------------------------------------------
  def predicted_damage(user:, target:, user_pokemon: nil, target_pokemon: nil)
    sim = nil
    prev_move = @ai.instance_variable_get(:@move)
    begin
      sim = setup_simulation(user, target, user_pokemon, target_pokemon)
      # Early return 0 for moves predicted to fail
      @ai.instance_variable_set(:@move, self)
      will_fail = (@ai.pbPredictMoveFailure rescue false) ||
                  (@ai.pbPredictMoveFailureAgainstTarget rescue false)
      return 0 if will_fail

      calc_type = self.rough_type
      dmg = self.rough_damage
      dmg = apply_damage_corrections(dmg, sim[:eff_user], sim[:user_sim], calc_type)
      dmg -= check_immunities(dmg, calc_type, sim[:eff_user], sim[:eff_target])

      # If target at full HP with Sturdy/Focus Sash and move would OHKO, cap at HP-1
      # Multi-hit moves bypass this protection
      if dmg >= sim[:eff_target].hp && sim[:eff_target].hp == sim[:eff_target].totalhp
        has_endure = sim[:eff_target].abilityActive? &&
                     sim[:eff_target].ability_id == :STURDY &&
                     !@ai.battle.moldBreaker
        has_sash = sim[:eff_target].itemActive? &&
                   sim[:eff_target].item_id == :FOCUSSASH
        if (has_endure || has_sash) && !@move.multiHitMove?
          dmg = sim[:eff_target].hp - 1
        end
      end

      return dmg
    ensure
      @ai.instance_variable_set(:@move, prev_move)
      restore_simulation(sim)
    end
  end

  # Calculate expected number of hits for multi-hit moves
  def expected_multi_hits(user_battler)
    # Population Bomb (10 hits, accuracy check per hit)
    if @move.is_a?(Battle::Move::HitTenTimes)
      return user_battler.hasActiveItem?(:LOADEDDICE) ? 7.0 : 5.0
    end
    # Fixed 3 hits (Triple Dive, Triple Axel, Triple Kick, etc.)
    if @move.is_a?(Battle::Move::HitThreeTimes)
      return 3.0
    end
    # 2-5 hit moves (Bullet Seed, Icicle Spear, etc.)
    if @move.is_a?(Battle::Move::HitTwoToFiveTimes)
      return 4.5 if user_battler.hasActiveAbility?(:SKILLLINK)
      return 4.5 if user_battler.hasActiveItem?(:LOADEDDICE)
      return 3.0
    end
    # Other multi-hit (Double Kick, etc. — fixed 2 hits)
    return 2.0 if @move.is_a?(Battle::Move::HitTwoTimes)
    return 1.0
  end
end

# Override MoveBasePower for 2-5 hit moves to account for Loaded Dice
Battle::AI::Handlers::MoveBasePower.add("HitTwoToFiveTimes",
  proc { |power, move, user, target, ai, battle|
    next power * 5 if user.has_active_ability?(:SKILLLINK)
    next power * 4 if user.has_active_item?(:LOADEDDICE)
    next power * 31 / 10   # Average damage dealt
  }
)
Battle::AI::Handlers::MoveBasePower.copy("HitTwoToFiveTimes",
                                         "HitTwoToFiveTimesRaiseUserSpd1LowerUserDef1")

Battle::AI::Handlers::MoveBasePower.add("HitTwoToFiveTimesOrThreeForAshGreninja",
  proc { |power, move, user, target, ai, battle|
    if user.battler.isSpecies?(:GRENINJA) && user.battler.form == 2
      next move.move.pbBaseDamage(power, user.battler, target.battler) * move.move.pbNumHits(user.battler, [target.battler])
    end
    next power * 5 if user.has_active_ability?(:SKILLLINK)
    next power * 4 if user.has_active_item?(:LOADEDDICE)
    next power * 31 / 10   # Average damage dealt
  }
)