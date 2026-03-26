#===============================================================================
# Move Simulation: Run actual pbCalcDamage silently for AI predictions.
# Entry point for the simulation system.
#===============================================================================

class Battle::AI
  #-----------------------------------------------------------------------------
  # Simulate a move's damage using the actual battle calculation.
  # Returns: { damage:, calc_damage:, critical:, type_mod:, target_fainted:,
  #            target_hp_remaining:, target_status:, user_hp_remaining: }
  #
  # Parameters:
  #   user_sim   - SimBattler (user of the move)
  #   target_sim - SimBattler (target of the move)
  #   move       - Battle::Move to simulate
  #   options    - Hash with optional settings:
  #     :deterministic - Use average damage roll (default: true)
  #     :include_effects - Also run move effects (default: false)
  #-----------------------------------------------------------------------------
  def simulate_move(user_sim, target_sim, move, options = {})
    deterministic = options.fetch(:deterministic, true)
    include_effects = options.fetch(:include_effects, false)

    # Configure SimBattle
    @sim_battle.deterministic = deterministic

    # Ensure SimBattlers are in SimBattle's battlers array
    @sim_battle.battlers[user_sim.index] = user_sim
    @sim_battle.battlers[target_sim.index] = target_sim

    # Link SimBattlers to SimBattle
    user_sim.sim_battle = @sim_battle
    target_sim.sim_battle = @sim_battle

    # Reset damage state
    target_sim.damageState.reset

    # Save original move battle reference
    saved_move_battle = move.instance_variable_get(:@battle)

    begin
      # Point move at SimBattle instead of real battle
      move.instance_variable_set(:@battle, @sim_battle)

      # Calculate move type
      move.instance_variable_set(:@calcType, move.pbCalcType(user_sim))

      # Run damage calculation for damaging moves
      if move.damagingMove?
        # Check for type immunity first
        calc_type = move.instance_variable_get(:@calcType) || move.type
        type_mod = move.pbCalcTypeMod(calc_type, user_sim, target_sim)
        target_sim.damageState.typeMod = type_mod

        if Effectiveness.ineffective?(type_mod)
          # Type immune - no damage
          target_sim.damageState.calcDamage = 0
          target_sim.damageState.hpLost = 0
        else
          # Check for ability immunities (Levitate, Flash Fire, etc.)
          immune = move.pbImmunityByAbility(user_sim, target_sim, false) rescue false
          if immune
            target_sim.damageState.calcDamage = 0
            target_sim.damageState.hpLost = 0
          else
            # Run actual damage calculation
            move.pbCalcDamage(user_sim, target_sim, 1)

            # Apply damage reduction (Sturdy, Focus Sash simulation, etc.)
            apply_sim_damage_reduction(user_sim, target_sim, move)
          end
        end
      end

      # Optionally run move effects
      if include_effects && !target_sim.fainted?
        begin
          move.pbEffectAgainstTarget(user_sim, target_sim)
        rescue => e
          PBDebug.log_ai("[simulate_move] Effect error: #{e.message}")
        end

        # Additional effect (status, stat drops with probability)
        if move.respond_to?(:pbAdditionalEffectChance)
          chance = move.pbAdditionalEffectChance(user_sim, target_sim)
          if chance > 0 && (deterministic ? chance >= 50 : rand(100) < chance)
            begin
              move.pbAdditionalEffect(user_sim, target_sim)
            rescue => e
              PBDebug.log_ai("[simulate_move] Additional effect error: #{e.message}")
            end
          end
        end
      end

      # Build result
      {
        damage: target_sim.damageState.hpLost,
        calc_damage: target_sim.damageState.calcDamage,
        critical: target_sim.damageState.critical,
        type_mod: target_sim.damageState.typeMod,
        target_fainted: target_sim.fainted?,
        target_hp_remaining: target_sim.hp,
        target_status: target_sim.status,
        target_stages: target_sim.stages.dup,
        user_hp_remaining: user_sim.hp,
        user_status: user_sim.status
      }
    ensure
      # Restore move's battle reference
      move.instance_variable_set(:@battle, saved_move_battle)

      # Clear sim_battle from battlers
      user_sim.sim_battle = nil
      target_sim.sim_battle = nil
    end
  end

  #-----------------------------------------------------------------------------
  # Apply damage reduction for Sturdy/Focus Sash/etc.
  # This is a simplified version - the real battle has more complex logic.
  #-----------------------------------------------------------------------------
  def apply_sim_damage_reduction(user, target, move)
    damage = target.damageState.calcDamage
    return if damage <= 0

    # Cap damage at target's HP
    damage = [damage, target.hp].min

    # Sturdy (survives with 1 HP from full)
    if target.hp == target.totalhp && damage >= target.hp
      if target.has_active_ability?(:STURDY) && !@battle.moldBreaker
        damage = target.hp - 1
        target.damageState.sturdy = true
      end
    end

    # Focus Sash (survives with 1 HP from full)
    if target.hp == target.totalhp && damage >= target.hp
      if target.has_active_item?(:FOCUSSASH)
        damage = target.hp - 1
        target.damageState.focusSash = true
      end
    end

    # Focus Band (10% chance to survive)
    if damage >= target.hp && target.has_active_item?(:FOCUSBAND)
      # In deterministic mode, don't apply (too unreliable)
    end

    # Disguise (Mimikyu)
    if target.has_active_ability?(:DISGUISE) && target.form == 0 && !@battle.moldBreaker
      damage = 0
      target.damageState.disguise = true
    end

    # Ice Face (Eiscue) - blocks physical moves
    if target.has_active_ability?(:ICEFACE) && target.form == 0 &&
       move.physicalMove? && !@battle.moldBreaker
      damage = 0
      target.damageState.iceFace = true
    end

    target.damageState.hpLost = damage
    target.damageState.totalHPLost += damage

    # Apply HP loss to SimBattler
    target.sim_hp -= damage if damage > 0
  end

  #-----------------------------------------------------------------------------
  # Simulate weather change from switch-in ability
  #-----------------------------------------------------------------------------
  def simulated_weather(switch_in_sim, current)
    return current unless switch_in_sim

    # Primal forms
    if switch_in_sim.isSpecies?(:KYOGRE) && switch_in_sim.has_active_item?(:BLUEORB)
      return :HeavyRain
    elsif switch_in_sim.isSpecies?(:GROUDON) && switch_in_sim.has_active_item?(:REDORB)
      return :HarshSun
    end

    new_weather = case switch_in_sim.ability_id
    when :DROUGHT, :ORICHALCUMPULSE then :Sun
    when :DRIZZLE                   then :Rain
    when :SANDSTREAM                then :Sandstorm
    when :SNOWWARNING               then :Hail
    when :DESOLATELAND              then :HarshSun
    when :PRIMORDIALSEA             then :HeavyRain
    when :DELTASTREAM               then :StrongWinds
    else return current
    end

    # Primal weather can't be overwritten by non-primal
    return current if current == :StrongWinds && new_weather != :StrongWinds
    return current if PRIMAL_WEATHERS.include?(current) && !PRIMAL_WEATHERS.include?(new_weather)

    new_weather
  end

  #-----------------------------------------------------------------------------
  # Simulate terrain change from switch-in ability
  #-----------------------------------------------------------------------------
  def simulated_terrain(switch_in_sim, current)
    return current unless switch_in_sim

    case switch_in_sim.ability_id
    when :ELECTRICSURGE, :HADRONENGINE then :Electric
    when :GRASSYSURGE                  then :Grassy
    when :MISTYSURGE                   then :Misty
    when :PSYCHICSURGE                 then :Psychic
    else current
    end
  end

  #-----------------------------------------------------------------------------
  # Simulate Intimidate on switch-in
  #-----------------------------------------------------------------------------
  INTIMIDATE_IMMUNE = [:CLEARBODY, :WHITESMOKE, :FULLMETALBODY,
                       :HYPERCUTTER, :INNERFOCUS, :OBLIVIOUS,
                       :OWNTEMPO, :SCRAPPY, :GUARDDOG].freeze

  def simulate_intimidate(user_sim, target_sim, switch_in)
    if switch_in == :user && user_sim.ability_id == :INTIMIDATE
      apply_sim_intimidate(target_sim)
    elsif switch_in == :target && target_sim.ability_id == :INTIMIDATE
      apply_sim_intimidate(user_sim)
    end
  end

  def apply_sim_intimidate(sim_battler)
    return if sim_battler.has_active_ability?(INTIMIDATE_IMMUNE) || @battle.moldBreaker
    current = sim_battler.sim_stages[:ATTACK] || 0
    sim_battler.sim_stages[:ATTACK] = [current - 1, -6].max
  end

  #-----------------------------------------------------------------------------
  # Get the best damage move for a battler against a target.
  # Returns: { move:, damage: } or nil if no damaging moves
  #-----------------------------------------------------------------------------
  def best_damage_move(attacker_sim, defender_sim)
    best = nil
    best_damage = 0

    attacker_sim.moves.each do |move|
      next unless move&.damagingMove?
      next unless attacker_sim.pbCanChooseMove?(move, false, false)

      result = simulate_move(attacker_sim, defender_sim, move)
      if result[:damage] > best_damage
        best_damage = result[:damage]
        best = { move: move, damage: result[:damage], result: result }
      end

      # Reset states for next simulation
      attacker_sim.reset_sim_state!
      defender_sim.reset_sim_state!
    end

    best
  end
end
