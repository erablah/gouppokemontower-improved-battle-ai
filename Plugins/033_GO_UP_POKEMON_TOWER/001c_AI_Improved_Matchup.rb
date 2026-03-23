#===============================================================================
# [AI_Improved_Matchup.rb] - 1v1 Simulation, Damage Caching, Matchup Analysis
# Split from 001_AI_Improved_Core.rb for separation of concerns.
#===============================================================================

class Battle::AI
  #---------------------------------------------------------------------------
  # [Helper] Stat stage multiplier: stage 0 = 1.0, +1 = 1.5, -1 = 0.667, etc.
  #---------------------------------------------------------------------------
  def stat_stage_mult(stage)
    s = stage.clamp(-6, 6)
    s >= 0 ? (2.0 + s) / 2.0 : 2.0 / (2.0 - s)
  end

  #---------------------------------------------------------------------------
  # [Helper] Extract simulation-relevant metadata from a Battle::Move.
  # Returns { stat_down: [...] or nil, drain_factor: Float, physical: bool, special: bool }
  #---------------------------------------------------------------------------
  def move_sim_modifiers(move)
    return { stat_down: nil, drain_factor: 0.0, physical: false, special: false } unless move
    mods = { stat_down: nil, drain_factor: 0.0 }
    # Drain detection (check subclass first to exclude conditional Dream Eater)
    if move.is_a?(Battle::Move::HealUserByHalfOfDamageDoneIfTargetAsleep)
      # Conditional drain — skip
    elsif move.is_a?(Battle::Move::HealUserByThreeQuartersOfDamageDone)
      mods[:drain_factor] = 0.75
    elsif move.is_a?(Battle::Move::HealUserByHalfOfDamageDone)
      mods[:drain_factor] = 0.5
    end
    # Stat-down detection (user self-drops after attacking)
    if move.respond_to?(:statDown) && move.statDown && move.damagingMove?
      mods[:stat_down] = move.statDown
    end
    mods[:physical] = move.physicalMove? rescue false
    mods[:special]  = move.specialMove? rescue false
    mods
  end

  #---------------------------------------------------------------------------
  # [Helper] Compute effective damage this turn given cumulative stat drops.
  # attacker_stages: the attacker's own cumulative self-drops (reduces their offense)
  # defender_stages: the defender's own cumulative self-drops (reduces their defense)
  #---------------------------------------------------------------------------
  def compute_effective_dmg(base_dmg, atk_mods, atk_stages, def_stages)
    mult = 1.0
    # Attacker's offensive stat drops reduce their outgoing damage
    if atk_mods[:stat_down]
      (atk_mods[:stat_down].length / 2).times do |i|
        stat = atk_mods[:stat_down][i * 2]
        if (stat == :ATTACK && atk_mods[:physical]) ||
           (stat == :SPECIAL_ATTACK && atk_mods[:special])
          stage = atk_stages[stat] || 0
          mult *= stat_stage_mult(stage) if stage != 0
        end
      end
    end
    # Defender's defensive stat drops increase damage they take
    if atk_mods[:physical]
      def_stage = def_stages[:DEFENSE] || 0
      mult /= stat_stage_mult(def_stage) if def_stage < 0
    elsif atk_mods[:special]
      spdef_stage = def_stages[:SPECIAL_DEFENSE] || 0
      mult /= stat_stage_mult(spdef_stage) if spdef_stage < 0
    end
    (base_dmg * mult).round
  end

  #---------------------------------------------------------------------------
  # [Helper] Accumulate stat drops into a stages hash (clamped at -6).
  #---------------------------------------------------------------------------
  def apply_sim_stat_drops(stages, stat_down)
    return unless stat_down
    (stat_down.length / 2).times do |i|
      stat = stat_down[i * 2]
      amount = stat_down[(i * 2) + 1]
      stages[stat] = [(stages[stat] || 0) - amount, -6].max
    end
  end

  #---------------------------------------------------------------------------
  # [Helper] Build a combatant hash from two on-field AIBattlers.
  # Returns { dmg:, move:, hp:, priority_dmg: }
  # Callers can .merge() overrides for hypothetical scenarios.
  #---------------------------------------------------------------------------
  def make_combatant(attacker, defender)
    dmg_data = damage_moves(attacker, defender)
    best = dmg_data.values.max_by { |md| md[:dmg] }
    {
      battler: attacker,
      target: defender,
      dmg: best&.dig(:dmg) || 0,
      move: best&.dig(:move),
      hp: attacker.hp
    }
  end

  #---------------------------------------------------------------------------
  # [Helper] Core 1v1 turn-by-turn simulation between two combatants.
  # u/f are combatant hashes with keys:
  #   :dmg, :move, :hp        — required
  #   :battler, :target       — optional AIBattler refs; used to auto-compute
  #                              :priority_dmg and :heal_per_turn/:self_dmg_per_turn
  #                              when those keys are not explicitly provided.
  #   :priority_dmg, :heal_per_turn, :self_dmg_per_turn — optional overrides
  # Returns a hash with KO-turn counts, win flag, and OHKO/2HKO booleans.
  #---------------------------------------------------------------------------
  def one_v_one_result(u, f, user_outspeeds)
    user_dmg = u[:dmg]; foe_dmg = f[:dmg]
    user_hp = u[:hp]; foe_hp = f[:hp]
    user_move = u[:move]; foe_move = f[:move]

    # Auto-compute priority_dmg from damage_moves if battler refs provided
    user_priority_dmg = u[:priority_dmg]
    if user_priority_dmg.nil? && u[:battler] && u[:target]
      pri = damage_moves(u[:battler], u[:target]).values
                .select { |md| md[:move].priority > 0 }.max_by { |md| md[:dmg] }
      user_priority_dmg = pri&.dig(:dmg) || 0
    end
    user_priority_dmg ||= 0

    foe_priority_dmg = f[:priority_dmg]
    if foe_priority_dmg.nil? && f[:battler] && f[:target]
      pri = damage_moves(f[:battler], f[:target]).values
                .select { |md| md[:move].priority > 0 }.max_by { |md| md[:dmg] }
      foe_priority_dmg = pri&.dig(:dmg) || 0
    end
    foe_priority_dmg ||= 0

    # Auto-compute EOR damage from battler if provided
    if u.key?(:heal_per_turn) || u.key?(:self_dmg_per_turn)
      user_heal_per_turn = u[:heal_per_turn] || 0
      user_self_dmg_per_turn = u[:self_dmg_per_turn] || 0
    elsif u[:battler]
      eor = u[:battler].rough_end_of_round_damage
      user_heal_per_turn = [-eor, 0].max
      user_self_dmg_per_turn = [eor, 0].max
    else
      user_heal_per_turn = 0; user_self_dmg_per_turn = 0
    end

    if f.key?(:heal_per_turn) || f.key?(:self_dmg_per_turn)
      foe_heal_per_turn = f[:heal_per_turn] || 0
      foe_self_dmg_per_turn = f[:self_dmg_per_turn] || 0
    elsif f[:battler]
      eor = f[:battler].rough_end_of_round_damage
      foe_heal_per_turn = [-eor, 0].max
      foe_self_dmg_per_turn = [eor, 0].max
    else
      foe_heal_per_turn = 0; foe_self_dmg_per_turn = 0
    end

    max_turns = 10
    u_mods = move_sim_modifiers(user_move)
    f_mods = move_sim_modifiers(foe_move)
    u_stages = {}
    f_stages = {}
    cur_u_hp = user_hp.to_f
    cur_f_hp = foe_hp.to_f
    u_turns = 999
    f_turns = 999

    (1..max_turns).each do |turn|
      # Effective damage this turn (accounting for cumulative stat drops)
      eff_u_dmg = compute_effective_dmg(user_dmg, u_mods, u_stages, f_stages)
      eff_f_dmg = compute_effective_dmg(foe_dmg, f_mods, f_stages, u_stages)

      # Priority check: use priority move to go first when it KOs, or when
      # the side is slower and would die to the opponent's attack this turn.
      u_can_pri_ko = user_priority_dmg > 0 && user_priority_dmg >= cur_f_hp
      f_can_pri_ko = foe_priority_dmg > 0 && foe_priority_dmg >= cur_u_hp
      u_pri_desperation = user_priority_dmg > 0 && !user_outspeeds && eff_f_dmg >= cur_u_hp
      f_pri_desperation = foe_priority_dmg > 0 && user_outspeeds && eff_u_dmg >= cur_f_hp
      u_uses_pri = u_can_pri_ko || u_pri_desperation
      f_uses_pri = f_can_pri_ko || f_pri_desperation
      if u_uses_pri && !f_uses_pri
        turn_user_first = true
      elsif f_uses_pri && !u_uses_pri
        turn_user_first = false
      else
        turn_user_first = user_outspeeds
      end

      if turn_user_first
        # --- User attacks ---
        actual_u_dmg = u_uses_pri ? user_priority_dmg : eff_u_dmg
        cur_f_hp -= actual_u_dmg
        cur_u_hp = [cur_u_hp + (u_mods[:drain_factor] * actual_u_dmg).round, user_hp].min
        if cur_f_hp <= 0
          u_turns = turn
          break
        end
        # --- Foe attacks ---
        actual_f_dmg = f_uses_pri ? foe_priority_dmg : eff_f_dmg
        cur_u_hp -= actual_f_dmg
        cur_f_hp = [cur_f_hp + (f_mods[:drain_factor] * actual_f_dmg).round, foe_hp].min
        if cur_u_hp <= 0
          f_turns = turn
          break
        end
      else
        # --- Foe attacks first ---
        actual_f_dmg = f_uses_pri ? foe_priority_dmg : eff_f_dmg
        cur_u_hp -= actual_f_dmg
        cur_f_hp = [cur_f_hp + (f_mods[:drain_factor] * actual_f_dmg).round, foe_hp].min
        if cur_u_hp <= 0
          f_turns = turn
          break
        end
        # --- User attacks ---
        actual_u_dmg = u_uses_pri ? user_priority_dmg : eff_u_dmg
        cur_f_hp -= actual_u_dmg
        cur_u_hp = [cur_u_hp + (u_mods[:drain_factor] * actual_u_dmg).round, user_hp].min
        if cur_f_hp <= 0
          u_turns = turn
          break
        end
      end

      # End-of-turn effects
      cur_u_hp = [cur_u_hp + user_heal_per_turn - user_self_dmg_per_turn, user_hp].min
      cur_f_hp = [cur_f_hp + foe_heal_per_turn - foe_self_dmg_per_turn, foe_hp].min
      if cur_u_hp <= 0
        f_turns = turn
        break
      end
      if cur_f_hp <= 0
        u_turns = turn
        break
      end

      # Accumulate stat drops for next turn
      apply_sim_stat_drops(u_stages, u_mods[:stat_down])
      apply_sim_stat_drops(f_stages, f_mods[:stat_down])
    end

    user_wins = (u_turns < f_turns) || (u_turns == f_turns && user_outspeeds)
    {
      u_turns:          u_turns,
      f_turns:          f_turns,
      user_wins:        user_wins,
      user_outspeeds:   user_outspeeds,
      foe_can_ohko:     f_turns <= 1,
      foe_can_2hko:     f_turns <= 2,
      user_can_ohko:    u_turns <= 1,
      user_can_2hko:    u_turns <= 2,
      user_hp_pct:      [cur_u_hp / [user_hp, 1].max.to_f, 0.0].max,
      foe_hp_pct:       [cur_f_hp / [foe_hp, 1].max.to_f, 0.0].max,
    }
  end

  #---------------------------------------------------------------------------
  # [Helper] Does a reserve (party) Pokemon outspeed an on-field foe AIBattler?
  # Creates a temporary Battler so pbSpeed accounts for abilities (Swift Swim,
  # Chlorophyll, Sand Rush, etc.), items (Choice Scarf), paralysis, Tailwind,
  # and other battle modifiers. Sticky Web's -1 Speed stage is pre-applied
  # since the reserve hasn't switched in yet.
  #---------------------------------------------------------------------------
  def reserve_outspeeds_foe?(pkmn, foe_battler, extra_stages: nil)
    pkmn_lagging = LAGGING_TAIL_ITEMS.include?(pkmn.item_id)
    foe_lagging  = LAGGING_TAIL_ITEMS.include?(foe_battler.battler.item_id) && foe_battler.battler.itemActive?
    if pkmn_lagging && !foe_lagging
      return false
    elsif foe_lagging && !pkmn_lagging
      return true
    end
    # Build a temporary battler to get a full pbSpeed calculation
    temp = Battle::Battler.new(@battle, @user.index)
    temp.pbInitialize(pkmn, 0)
    # Apply passed-in stages (e.g. Baton Pass boosts)
    if extra_stages
      extra_stages.each { |stat, stage| temp.stages[stat] = stage.clamp(-6, 6) }
    end
    # Pre-apply Sticky Web's -1 Speed stage for grounded non-boots pkmn (stacks)
    if @user.pbOwnSide.effects[PBEffects::StickyWeb] &&
       !pkmn.hasItem?(:HEAVYDUTYBOOTS) && !pokemon_airborne?(pkmn)
      temp.stages[:SPEED] = [(temp.stages[:SPEED] || 0) - 1, -6].max
    end
    pkmn_speed = temp.pbSpeed
    foe_speed  = foe_battler.rough_stat(:SPEED)
    trick_room = @battle.field.effects[PBEffects::TrickRoom] > 0
    return (pkmn_speed > foe_speed) ^ trick_room
  end

  # Returns {move_id => {move: Battle::Move, dmg: int}}
  # Computes predicted_damage for each of attacker's damaging moves against defender, cached per turn.
  # - attacker/defender are AIBattler instances (attacker.index and defender.index are Integers)
  # - keyed by move ID (symbol) for O(1) lookup of a specific move's damage
  # - cache key uses battler indexes; both directions stored separately (e.g. [0,1] != [1,0])
  def damage_moves(attacker, defender)
    mega = @battle.pbRegisteredMegaEvolution?(attacker.index) rescue false
    tera = (@battle.pbRegisteredTerastallize?(attacker.index) rescue false) || attacker.battler.tera?
    def_tera = defender.battler.tera?
    key = [attacker.index, defender.index, @battle.turnCount, mega, tera, def_tera,
           attacker.battler.pokemon&.personalID, defender.battler.pokemon&.personalID]
    (@_ai_dmg_cache ||= {})[key] ||= begin
      PBDebug.log_ai("[damage_moves] computing #{attacker.name} → #{defender.name} (turn #{@battle.turnCount})")
      moves_by_id = {}
      moves_list = (attacker.side != @user.side) ? known_foe_moves(attacker) : attacker.battler.moves
      moves_list.each do |m|
        next unless m&.damagingMove?
        next unless attacker.battler.pbCanChooseMove?(m, false, false)
        sim = Battle::AI::AIMove.new(self)
        sim.set_up(m)
        dmg = sim.predicted_damage(user: attacker, target: defender) || 0
        pct_total = (100.0 * dmg / [1, defender.battler.totalhp].max).round(1)
        pct_hp    = (100.0 * dmg / [1, defender.hp].max).round(1)
        PBDebug.log_ai("  #{m.name}: #{dmg} dmg (#{pct_total}% totalhp / #{pct_hp}% curhp)")
        moves_by_id[m.id] = { move: m, dmg: dmg }
      end
      moves_by_id
    end
  end

  # Returns a cached summary of KO/speed data for all current battler pairs.
  # Reuses damage_moves cache — no redundant computation.
  def matchup_summary
    mega = @battle.pbRegisteredMegaEvolution?(@user.index) rescue false
    tera = (@battle.pbRegisteredTerastallize?(@user.index) rescue false) || @user.battler.tera?
    foe_ids = []
    each_foe_battler(@user.side) { |b, _| foe_ids << b.battler.pokemon&.personalID }
    key = [@user.index, @battle.turnCount, mega, tera, @user.battler.pokemon&.personalID, foe_ids]
    (@_matchup_cache ||= {})[key] ||= begin
      summary = { foes: {} }
      user_speed = @user.rough_stat(:SPEED)
      summary[:user_speed] = user_speed
      summary[:foe_can_ohko] = false
      summary[:foe_can_ohko_and_outspeeds] = false
      summary[:user_can_ko_any] = false
      summary[:max_foe_dmg] = 0

      each_foe_battler(@user.side) do |b, _i|
        user_c = make_combatant(@user, b)
        foe_c  = make_combatant(b, @user)

        foe_speed = b.rough_stat(:SPEED)
        foe_outspeeds = b.faster_than?(@user)
        foe_has_priority = foe_c[:move] && foe_c[:move].priority > 0
        foe_effectively_outspeeds = foe_outspeeds || foe_has_priority

        one_v_one = one_v_one_result(user_c, foe_c, !foe_outspeeds)

        foe_entry = {
          best_dmg:    foe_c[:dmg],
          best_move:   foe_c[:move],
          best_priority: foe_c[:move] ? foe_c[:move].priority : 0,
          user_best_dmg: user_c[:dmg],
          speed:       foe_speed,
          outspeeds:   foe_outspeeds,
          effectively_outspeeds: foe_effectively_outspeeds,
          can_ohko:    one_v_one[:foe_can_ohko],
          foe_hp:      b.hp,
          foe_totalhp: b.battler.totalhp,
          one_v_one:   one_v_one,
        }
        foe_entry[:switch_prediction_roll] = pbAIRandom(100)
        summary[:foes][b.index] = foe_entry
        summary[:max_foe_dmg] = [summary[:max_foe_dmg], foe_c[:dmg]].max
        summary[:foe_can_ohko] = true if foe_entry[:can_ohko]
        summary[:foe_can_ohko_and_outspeeds] = true if foe_entry[:can_ohko] && foe_effectively_outspeeds
        summary[:user_can_ko_any] = true if one_v_one[:user_can_ohko]
      end
      summary
    end
  end

  #---------------------------------------------------------------------------
  # Fog of War: returns the list of moves the AI "knows" about for a foe.
  # If the foe has never acted, one non-STAB move may be hidden (50% chance).
  # Result is cached per [battler.index, turnCount] for consistency.
  #---------------------------------------------------------------------------
  def known_foe_moves(foe_ai_battler)
    cache_key = [foe_ai_battler.index, @battle.turnCount, foe_ai_battler.battler.pokemon&.personalID]
    (@_known_foe_moves_cache ||= {})[cache_key] ||= begin
      all_moves = foe_ai_battler.battler.moves.compact
      acted_ids = @battle.instance_variable_get(:@_foe_acted_ids) || {}
      pkmn = foe_ai_battler.battler.pokemon

      if pkmn && acted_ids[pkmn.personalID]
        # Foe has acted before — full knowledge
        all_moves
      else
        # Foe has never acted — protect best STAB moves, maybe hide one other
        foe_types = foe_ai_battler.battler.pbTypes(true)
        # For each type, find the highest-power STAB move
        protected_moves = []
        foe_types.each do |t|
          best = all_moves.select { |m| m.type == t && m.damagingMove? }
                          .max_by { |m| m.power }
          protected_moves << best if best
        end

        remaining = all_moves - protected_moves
        if remaining.length > 0 && pbAIRandom(100) < 50
          hide = remaining[pbAIRandom(remaining.length)]
          result = all_moves - [hide]
          PBDebug.log_ai("[known_foe_moves] Hiding #{hide.name} from #{foe_ai_battler.name} (never acted)")
          result
        else
          all_moves
        end
      end
    end
  end
end
