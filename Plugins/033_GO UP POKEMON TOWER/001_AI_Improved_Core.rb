#===============================================================================
# [AI_Improved.rb] - Safe Move-Scoring AI for Pokémon Essentials v21.1
# - DBK / Doubles / Raid compatible
#===============================================================================

#-------------------------------------------------------------------------------
# Fog of War: track any battler that uses a move so the AI knows they've acted
#-------------------------------------------------------------------------------
class Battle::Battler
  alias _tower_fog_pbProcessTurn pbProcessTurn
  def pbProcessTurn(choice, tryFlee = true)
    ret = _tower_fog_pbProcessTurn(choice, tryFlee)
    if choice[0] == :UseMove && self.pokemon
      acted = @battle.instance_variable_get(:@_foe_acted_ids) || {}
      acted[self.pokemon.personalID] = true
      @battle.instance_variable_set(:@_foe_acted_ids, acted)
    end
    ret
  end

  # Fix: Struggle is blocked by Choice lock during the attack phase because
  # pbTryUseMove calls pbCanChooseMove?, which rejects any move that isn't the
  # Choice-locked move. Struggle should always be usable.
  alias _tower_struggle_pbCanChooseMove pbCanChooseMove?
  def pbCanChooseMove?(move, commandPhase, showMessages = true, specialUsage = false)
    return true if move.is_a?(Battle::Move::Struggle)
    return _tower_struggle_pbCanChooseMove(move, commandPhase, showMessages, specialUsage)
  end
end

class Battle::AI
  MOVE_FAIL_SCORE = -999
  REPLACEMENT_THRESHOLD_NORMAL = 120
  REPLACEMENT_THRESHOLD_TERRIBLE_MOVES = 60

  #=============================================================================
  # KO Race Simulation Constants
  #=============================================================================
  # Stat-dropping moves: function_code => { stat => stages }
  STAT_DROP_MOVES = {
    "LowerUserSpAtk2" => { spa: -2 },                    # Draco Meteor, Overheat, Leaf Storm, Psycho Boost
    "LowerUserAtkDef1" => { atk: -1, def: -1 },          # Superpower, Close Combat (uses different code)
    "LowerUserDefSpDef1" => { def: -1, spd: -1 },        # Close Combat
    "LowerUserDefSpDefSpd1" => { def: -1, spd: -1, spe: -1 }, # V-Create
    "LowerUserSpAtk1" => { spa: -1 },                    # Mystical Fire (some variants)
    "LowerUserAtk1" => { atk: -1 },                      # Some weaker moves
  }.freeze

  # Draining move function codes and their drain ratios
  DRAIN_MOVE_RATIOS = {
    "HealUserByHalfOfDamageDone" => 0.5,          # Drain Punch, Giga Drain, Leech Life
    "HealUserByThreeQuartersOfDamageDone" => 0.75, # Draining Kiss, Oblivion Wing
    "UserTargetAverageHP" => 0.0,                 # Pain Split (special case, not drain)
  }.freeze

  # Mold Breaker-like abilities that bypass Unaware
  MOLD_BREAKER_ABILITIES = [:MOLDBREAKER, :TERAVOLT, :TURBOBLAZE].freeze

  #---------------------------------------------------------------------------
  # [Helper] Convert effectiveness multiplier to float
  #---------------------------------------------------------------------------
  def pbGetEffectivenessMult(effectiveness_id)
    return effectiveness_id.to_f / 100.0
  end


  # Override: replace -1 sentinel with MOVE_FAIL_SCORE for failed moves,
  # so negative penalty scores aren't confused with move failures.
  def pbGetMoveScoreAgainstTarget
    if @trainer.has_skill_flag?("PredictMoveFailure") && pbPredictMoveFailureAgainstTarget
      PBDebug.log("     move will not affect #{@target.name}")
      PBDebug.log_score_change(MOVE_FAIL_SCORE - MOVE_BASE_SCORE, "move will fail")
      return MOVE_FAIL_SCORE
    end
    score = MOVE_BASE_SCORE
    if @trainer.has_skill_flag?("ScoreMoves")
      old_score = score
      score = Battle::AI::Handlers.apply_move_effect_against_target_score(@move.function_code,
         MOVE_BASE_SCORE, @move, @user, @target, self, @battle)
      PBDebug.log_score_change(score - old_score, "function code modifier (against target)")
      score = Battle::AI::Handlers.apply_general_move_against_target_score_modifiers(
        score, @move, @user, @target, self, @battle)
    end
    target_data = @move.pbTarget(@user.battler)
    if pbShouldInvertScore?(target_data)
      if score == MOVE_USELESS_SCORE
        PBDebug.log("     move is useless against #{@target.name}")
        return MOVE_FAIL_SCORE
      end
      old_score = score
      score = ((1.85 * MOVE_BASE_SCORE) - score).to_i
      PBDebug.log_score_change(score - old_score, "score inverted (move targets ally but can target foe)")
    end
    return score
  end

  # Override: scale stat-change scores by additional effect chance for damaging
  # moves with < 100% effect probability (e.g. Moonblast's 30% SpA drop).
  alias_method :orig_get_score_for_target_stat_drop, :get_score_for_target_stat_drop
  def get_score_for_target_stat_drop(score, target, stat_changes, whole_effect = true,
                                     fixed_change = false, ignore_contrary = false)
    result = orig_get_score_for_target_stat_drop(score, target, stat_changes, whole_effect, fixed_change, ignore_contrary)
    if @move.damagingMove? && @move.move.addlEffect > 0 && @move.move.addlEffect < 100
      delta = result - score
      if delta != 0
        chance = @move.move.addlEffect
        chance = [chance * 2, 100].min if @user.has_active_ability?(:SERENEGRACE)
        scaled_delta = (delta * chance / 100.0).round
        PBDebug.log("     [additional effect scaling] stat drop: #{delta} * #{chance}% = #{scaled_delta}")
        result = score + scaled_delta
      end
    end
    return result
  end

  alias_method :orig_get_score_for_target_stat_raise, :get_score_for_target_stat_raise
  def get_score_for_target_stat_raise(score, target, stat_changes, whole_effect = true,
                                      fixed_change = false, ignore_contrary = false)
    result = orig_get_score_for_target_stat_raise(score, target, stat_changes, whole_effect, fixed_change, ignore_contrary)
    if @move.damagingMove? && @move.move.addlEffect > 0 && @move.move.addlEffect < 100
      delta = result - score
      if delta != 0
        chance = @move.move.addlEffect
        chance = [chance * 2, 100].min if @user.has_active_ability?(:SERENEGRACE)
        scaled_delta = (delta * chance / 100.0).round
        PBDebug.log("     [additional effect scaling] stat raise: #{delta} * #{chance}% = #{scaled_delta}")
        result = score + scaled_delta
      end
    end
    return result
  end

  # Override: Returns whether the move will definitely fail (assuming no battle conditions
  # change between now and using the move).
  def pbPredictMoveFailure
    # User is awake and can't use moves that are only usable when asleep
    return true if !@user.battler.asleep? && @move.move.usableWhenAsleep?
    # NOTE: Truanting is not considered, because if it is, a Pokémon with Truant
    #       will want to switch due to terrible moves every other round (because
    #       all of its moves will fail), and this is disruptive and shouldn't be
    #       how such Pokémon behave.
    # Primal weather
    return true if @battle.pbWeather == :HeavyRain && @move.rough_type == :FIRE
    return true if @battle.pbWeather == :HarshSun && @move.rough_type == :WATER
    # Move effect-specific checks
    return true if Battle::AI::Handlers.move_will_fail?(@move.function_code, @move, @user, self, @battle)
    return false
  end

  # Override: remove the core engine's score = 0 clamp (line 284) so negative
  # scores from penalties are preserved, letting the AI pick the least-bad move.
  def pbGetMoveScore(targets = nil)
    score = MOVE_BASE_SCORE
    if targets
      score = 0
      affected_targets = 0
      orig_move = @move.move
      targets.each do |target|
        set_up_move_check(orig_move)
        set_up_move_check_target(target)
        t_score = pbGetMoveScoreAgainstTarget
        next if t_score <= MOVE_FAIL_SCORE
        score += t_score
        affected_targets += 1
      end
      if affected_targets == 0
        score = (@trainer.has_skill_flag?("PredictMoveFailure")) ? MOVE_USELESS_SCORE : MOVE_BASE_SCORE
      end
      if affected_targets == 0 && @trainer.has_skill_flag?("PredictMoveFailure")
        if !@move.move.worksWithNoTargets?
          PBDebug.log_score_change(MOVE_FAIL_SCORE, "move will fail")
          return MOVE_FAIL_SCORE
        end
      else
        score /= affected_targets if affected_targets > 1
        if @trainer.has_skill_flag?("PreferMultiTargetMoves") && affected_targets > 1
          old_score = score
          score += (affected_targets - 1) * 10
          PBDebug.log_score_change(score - old_score, "affects multiple battlers")
        end
      end
    end
    if @trainer.has_skill_flag?("ScoreMoves")
      old_score = score
      score = Battle::AI::Handlers.apply_move_effect_score(@move.function_code,
         score, @move, @user, self, @battle)
      PBDebug.log_score_change(score - old_score, "function code modifier (generic)")
      score = Battle::AI::Handlers.apply_general_move_score_modifiers(
        score, @move, @user, self, @battle)
    end
    return score.to_i
  end

  # override: only one tera available per team.
  alias wants_to_terastallize_original wants_to_terastallize?
  def wants_to_terastallize?
        return @user.get_total_tera_score >= 0
  end

  def safe_function_code(move)
    return nil if !move || !move.respond_to?(:function_code)
    return move.function_code
  end

  def safe_types(obj)
    return [] if !obj
    return obj.pbTypes(true) if obj.respond_to?(:pbTypes)
    return obj.types if obj.respond_to?(:types)
    return []
  end

  #=============================================================================
  # KO Race Simulation System (high_skill trainers only)
  #=============================================================================

  #---------------------------------------------------------------------------
  # Stat stage multiplier: converts stage (-6 to +6) to damage multiplier
  #---------------------------------------------------------------------------
  def stat_stage_multiplier(stage)
    stage = stage.clamp(-6, 6)
    if stage >= 0
      return (2.0 + stage) / 2.0
    else
      return 2.0 / (2.0 - stage)
    end
  end

  #---------------------------------------------------------------------------
  # Apply stat stage boost to a base stat value
  #---------------------------------------------------------------------------
  def apply_stage_boost(base_stat, stages)
    return base_stat if stages == 0
    mult = stat_stage_multiplier(stages)
    return (base_stat * mult).floor
  end

  #---------------------------------------------------------------------------
  # Get boost stages from a setup move
  # Returns hash like { atk: 1, spe: 1 } for Dragon Dance
  #---------------------------------------------------------------------------
  def get_boost_stages(setup_move)
    return {} unless setup_move
    real_move = setup_move.respond_to?(:move) ? setup_move.move : setup_move
    return {} unless real_move.respond_to?(:statUp)
    stat_up = real_move.statUp
    return {} unless stat_up

    boosts = {}
    (stat_up.length / 2).times do |i|
      stat_id = stat_up[i * 2]
      stages = stat_up[i * 2 + 1]
      case stat_id
      when :ATTACK then boosts[:atk] = stages
      when :DEFENSE then boosts[:def] = stages
      when :SPECIAL_ATTACK then boosts[:spa] = stages
      when :SPECIAL_DEFENSE then boosts[:spd] = stages
      when :SPEED then boosts[:spe] = stages
      when :ACCURACY then boosts[:acc] = stages
      when :EVASION then boosts[:eva] = stages
      end
    end
    boosts
  end

  #---------------------------------------------------------------------------
  # Get drain ratio for a move (0.0 if not a draining move)
  #---------------------------------------------------------------------------
  def drain_ratio(move)
    return 0.0 unless move
    func_code = move.respond_to?(:function_code) ? move.function_code : nil
    return DRAIN_MOVE_RATIOS[func_code] || 0.0
  end

  #---------------------------------------------------------------------------
  # Check if user has Mold Breaker-like ability (bypasses Unaware)
  #---------------------------------------------------------------------------
  def has_mold_breaker?(user)
    return false unless user
    ability = user.respond_to?(:ability_id) ? user.ability_id : nil
    ability ||= user.battler.ability_id if user.respond_to?(:battler)
    MOLD_BREAKER_ABILITIES.include?(ability)
  end

  #---------------------------------------------------------------------------
  # Check who acts first based on priority and speed
  #---------------------------------------------------------------------------
  def acts_first?(user, target, user_move, target_move, user_speed, target_speed)
    user_priority = user_move&.priority || 0
    target_priority = target_move&.priority || 0

    # Priority tier takes precedence
    return user_priority > target_priority if user_priority != target_priority

    # Same priority: speed comparison
    user_speed > target_speed
  end

  #---------------------------------------------------------------------------
  # Get the best damage move a battler can use against a target
  # Returns { move: Battle::Move, dmg: Integer }
  #---------------------------------------------------------------------------
  def best_damage_move_against(attacker, defender)
    dmg_data = damage_moves(attacker, defender)
    best = dmg_data.values.max_by { |md| md[:dmg] }
    return { move: best&.dig(:move), dmg: best&.dig(:dmg) || 0 }
  end

  #---------------------------------------------------------------------------
  # Calculate turns to KO accounting for stat-dropping moves
  # base_dmg: UNBOOSTED damage (stage 0)
  # current_stage: user's current offensive stage before setup
  # setup_boost: additional boost from setup move (0 if no setup)
  #---------------------------------------------------------------------------
  def calculate_turns_to_ko(ai_move, user, target, base_dmg, current_stage = 0, setup_boost = 0)
    return 999 if base_dmg <= 0

    move = ai_move.respond_to?(:move) ? ai_move.move : ai_move
    func_code = move.respond_to?(:function_code) ? move.function_code : nil
    stat_drops = STAT_DROP_MOVES[func_code]

    # Check for abilities
    has_contrary = user.has_active_ability?(:CONTRARY)
    has_simple = user.has_active_ability?(:SIMPLE)

    # Simple doubles setup boost (current_stage already reflects Simple from battle)
    effective_setup = has_simple ? setup_boost * 2 : setup_boost
    effective_setup = -effective_setup if has_contrary

    remaining_hp = target.hp
    # Start at current stage + setup boost
    cumulative_stage = (current_stage + effective_setup).clamp(-6, 6)
    turns = 0

    while remaining_hp > 0 && turns < 10
      stage_modifier = stat_stage_multiplier(cumulative_stage)
      turn_damage = (base_dmg * stage_modifier).floor
      turn_damage = [turn_damage, 1].max

      remaining_hp -= turn_damage
      turns += 1

      # Apply stat drop after attack (if applicable)
      if stat_drops && remaining_hp > 0
        offensive_drop = stat_drops[:atk] || stat_drops[:spa] || 0
        effective_drop = has_simple ? offensive_drop * 2 : offensive_drop
        effective_drop = -effective_drop if has_contrary
        cumulative_stage += effective_drop
        cumulative_stage = cumulative_stage.clamp(-6, 6)
      end
    end

    turns
  end

  #---------------------------------------------------------------------------
  # Simulate KO race between user and target
  # Returns hash with outcome details:
  #   :result - :user_wins or :target_wins
  #   :turns - number of turns to end battle
  #   :user_dmg_dealt - total damage dealt by user
  #   :target_dmg_dealt - total damage dealt by target
  #   :user_hp_remaining - HP at end
  #   :target_hp_remaining - HP at end
  #---------------------------------------------------------------------------
  def simulate_ko_race(user, target, user_move, setup_move: nil, cached_user_dmg: nil)
    # Get move objects
    ai_move = user_move.is_a?(Battle::AI::AIMove) ? user_move : nil
    if ai_move.nil?
      ai_move = Battle::AI::AIMove.new(self)
      ai_move.set_up(user_move)
    end

    # Check Unaware on target - setup is useless
    if setup_move && target.has_active_ability?(:UNAWARE) && !has_mold_breaker?(user)
      # Setup won't help against Unaware, simulate without it
      result = simulate_ko_race(user, target, user_move, setup_move: nil, cached_user_dmg: cached_user_dmg)
      return result
    end

    # Calculate effective speeds
    user_base_speed = user.rough_stat(:SPEED)
    target_speed = target.rough_stat(:SPEED)

    # Get boost stages from setup move
    boost_stages = setup_move ? get_boost_stages(setup_move) : {}
    speed_boost = boost_stages[:spe] || 0
    setup_offensive_boost = boost_stages[:atk] || boost_stages[:spa] || 0

    # Apply Simple/Contrary to speed boost (offensive boost handled in calculate_turns_to_ko)
    if user.has_active_ability?(:SIMPLE)
      speed_boost *= 2
    end
    if user.has_active_ability?(:CONTRARY)
      speed_boost = -speed_boost
    end
    speed_boost = speed_boost.clamp(-6, 6)

    user_boosted_speed = apply_stage_boost(user_base_speed, speed_boost)

    # Get user's base damage - use cached value if provided (ensures consistency with damage_moves cache)
    boosted_user_dmg = cached_user_dmg || ai_move.predicted_damage(user: user, target: target)
    if boosted_user_dmg <= 0  # Can't damage target
      return { result: :target_wins, turns: 1, user_dmg_dealt: 0, target_dmg_dealt: user.hp,
               user_hp_remaining: 0, target_hp_remaining: target.hp }
    end

    # Get user's current offensive stage to calculate unboosted damage
    move_obj = ai_move.respond_to?(:move) ? ai_move.move : user_move
    is_physical = move_obj.physicalMove?
    current_offensive_stage = is_physical ? user.stages[:ATTACK] : user.stages[:SPECIAL_ATTACK]
    current_offensive_stage ||= 0

    # Calculate unboosted damage (stage 0) from current boosted damage
    current_stage_mult = stat_stage_multiplier(current_offensive_stage)
    unboosted_user_dmg = (boosted_user_dmg / current_stage_mult).round
    unboosted_user_dmg = [unboosted_user_dmg, 1].max if boosted_user_dmg > 0

    # Get target's best damage move against user
    target_best = best_damage_move_against(target, user)
    target_dmg = target_best[:dmg]
    target_move = target_best[:move]

    if target_dmg <= 0  # Target can't damage user
      turns_to_ko = (target.hp.to_f / boosted_user_dmg).ceil
      return { result: :user_wins, turns: turns_to_ko, user_dmg_dealt: target.hp, target_dmg_dealt: 0,
               user_hp_remaining: user.hp, target_hp_remaining: 0 }
    end

    # Calculate turns to KO with proper stage handling
    # Pass unboosted damage, current stage, and setup boost
    user_turns = calculate_turns_to_ko(ai_move, user, target, unboosted_user_dmg, current_offensive_stage, setup_offensive_boost)
    target_turns = calculate_turns_to_ko_simple(target_dmg, user.hp)

    PBDebug.log_ai("[KO Race Debug] #{user.name} vs #{target.name}: boosted_dmg=#{boosted_user_dmg}, unboosted_dmg=#{unboosted_user_dmg}, stage=#{current_offensive_stage}, target_dmg=#{target_dmg}, user_hp=#{user.hp}, target_hp=#{target.hp}")
    PBDebug.log_ai("[KO Race Debug] user_turns=#{user_turns}, target_turns=#{target_turns}")

    # Setup costs a turn
    user_turns += 1 if setup_move

    # Determine who acts first
    if setup_move
      user_first = acts_first?(user, target, user_move, target_move, user_boosted_speed, target_speed)
    else
      user_first = acts_first?(user, target, user_move, target_move, user_base_speed, target_speed)
    end

    # Get item/ability info for HP simulation
    user_drain = drain_ratio(ai_move.respond_to?(:move) ? ai_move.move : user_move)
    user_drain *= 1.3 if user_drain > 0 && user.has_active_item?(:BIGROOT)
    user_leftovers = user.has_active_item?(:LEFTOVERS) ? user.battler.totalhp / 16 : 0
    target_leftovers = target.has_active_item?(:LEFTOVERS) ? target.battler.totalhp / 16 : 0
    user_life_orb = user.has_active_item?(:LIFEORB) ? user.battler.totalhp / 10 : 0

    # Simulate KO race turn by turn
    user_hp = user.hp
    target_hp = target.hp
    turns = 0
    max_turns = 20
    user_dmg_dealt = 0
    target_dmg_dealt = 0

    # Helper to build result hash
    build_result = lambda do |result|
      {
        result: result,
        turns: turns,
        user_dmg_dealt: user_dmg_dealt,
        target_dmg_dealt: target_dmg_dealt,
        user_hp_remaining: [user_hp, 0].max,
        target_hp_remaining: [target_hp, 0].max
      }
    end

    # Setup costs first turn (user doesn't attack, but foe does)
    if setup_move
      turns += 1
      user_hp -= target_dmg  # Foe attacks during setup turn
      target_dmg_dealt += target_dmg
      user_hp += user_leftovers
      user_hp = [user_hp, user.battler.totalhp].min
      return build_result.call(:target_wins) if user_hp <= 0
    end

    while turns < max_turns
      turns += 1

      if user_first
        # User attacks first
        target_hp -= boosted_user_dmg
        user_dmg_dealt += boosted_user_dmg
        user_hp -= user_life_orb if user_life_orb > 0
        user_hp += (boosted_user_dmg * user_drain).floor if user_drain > 0
        user_hp = [user_hp, user.battler.totalhp].min
        break if target_hp <= 0  # User wins
        return build_result.call(:target_wins) if user_hp <= 0  # User died to Life Orb

        # Target attacks second
        user_hp -= target_dmg
        target_dmg_dealt += target_dmg
        return build_result.call(:target_wins) if user_hp <= 0  # Target wins
      else
        # Target attacks first
        user_hp -= target_dmg
        target_dmg_dealt += target_dmg
        return build_result.call(:target_wins) if user_hp <= 0  # Target wins

        # User attacks second
        target_hp -= boosted_user_dmg
        user_dmg_dealt += boosted_user_dmg
        user_hp -= user_life_orb if user_life_orb > 0
        user_hp += (boosted_user_dmg * user_drain).floor if user_drain > 0
        user_hp = [user_hp, user.battler.totalhp].min
        break if target_hp <= 0  # User wins
        return build_result.call(:target_wins) if user_hp <= 0  # User died to Life Orb
      end

      # End of turn: Leftovers healing
      user_hp += user_leftovers
      user_hp = [user_hp, user.battler.totalhp].min
      target_hp += target_leftovers
      target_hp = [target_hp, target.battler.totalhp].min
    end

    PBDebug.log_ai("[KO Race Debug] user_speed=#{user_base_speed}, target_speed=#{target_speed}, user_first=#{user_first}, turns=#{turns}")

    # If we broke out of the loop, target_hp <= 0, so user wins
    return build_result.call(:user_wins)
  end

  #---------------------------------------------------------------------------
  # Simple turns to KO calculation (no stat drops)
  #---------------------------------------------------------------------------
  def calculate_turns_to_ko_simple(damage_per_hit, target_hp)
    return 999 if damage_per_hit <= 0
    (target_hp.to_f / damage_per_hit).ceil
  end

  #---------------------------------------------------------------------------
  # Check if a move is a setup move (raises user's stats)
  #---------------------------------------------------------------------------
  def is_setup_move?(move)
    return false unless move
    func_code = safe_function_code(move)
    return false unless func_code
    func_code.start_with?("RaiseUser")
  end

  #---------------------------------------------------------------------------
  # Get all setup moves from a battler's moveset
  #---------------------------------------------------------------------------
  def get_setup_moves(battler)
    moves = battler.respond_to?(:battler) ? battler.battler.moves : battler.moves
    moves.compact.select { |m| is_setup_move?(m) && (m.pp > 0 || m.total_pp == 0) }
  end

  #---------------------------------------------------------------------------
  # Get all damaging moves from a battler's moveset
  #---------------------------------------------------------------------------
  def get_damage_moves(battler)
    moves = battler.respond_to?(:battler) ? battler.battler.moves : battler.moves
    moves.compact.select { |m| m.damagingMove? && (m.pp > 0 || m.total_pp == 0) }
  end

   # override stat raise generic
  def get_target_stat_raise_score_generic(score, target, stat_changes, desire_mult = 1)
    return score
  end

  # override stat drop generic
  def get_target_stat_drop_score_generic(score, target, stat_changes, desire_mult = 1)
    return score
  end

  #---------------------------------------------------------------------------
  # Override: move item evaluation AFTER move scoring so the AI can compare
  # item value against best available move before committing.
  #---------------------------------------------------------------------------
  def pbDefaultChooseEnemyCommand(idxBattler)
    set_up(idxBattler)
    # 1. Proactive switch check (unchanged)
    ret = false
    PBDebug.logonerr { ret = pbChooseToSwitchOut }
    if ret
      PBDebug.log("")
      return
    end
    # 2. Special commands (Mega, Dynamax, etc.)
    ret = false
    PBDebug.logonerr { ret = pbChooseToUseSpecialCommand }
    if ret
      PBDebug.log("")
      return
    end
    if @battle.pbAutoFightMenu(idxBattler)
      PBDebug.log("")
      return
    end
    pbRegisterEnemySpecialAction(idxBattler)

    # 3. KO race decision system (always returns a concrete decision)
    ko_race_choice = pbGetKORaceChoice
    PBDebug.log_ai("[KO Race Decision] Using KO race choice: #{ko_race_choice[:type]}")
    case ko_race_choice[:type]
    when :damage, :setup, :fallback_damage
      # Use the chosen move
      move = ko_race_choice[:move]
      move_idx = @user.battler.moves.index(move)
      if move_idx && @battle.pbCanChooseMove?(@user.index, move_idx, false)
        target_idx = ko_race_choice[:target] || -1
        @battle.pbRegisterMove(@user.index, move_idx, false)
        @battle.pbRegisterTarget(@user.index, target_idx) if target_idx >= 0
        PBDebug.log_ai("=> will use #{move.name} (KO race #{ko_race_choice[:type]})")
        PBDebug.log("")
        pbRegisterEnemySpecialAction2(idxBattler)
        return
      end
    when :utility
      # Utility move scored highly, use it
      choices = ko_race_choice[:choices]
      if choices && !choices.empty?
        pbChooseMove(choices)
        PBDebug.log("")
        pbRegisterEnemySpecialAction2(idxBattler)
        return
      end
    when :switch
      # KO race suggests switching - use unified context-based selection
      idxParty = choose_best_replacement_pokemon(@user.index, false, false)
      if idxParty >= 0 && @battle.pbRegisterSwitch(@user.index, idxParty)
        PBDebug.log_ai("=> will switch (KO race)")
        PBDebug.log("")
        return
      end
    when :item
      # Use the item
      item = ko_race_choice[:item]
      target = ko_race_choice[:target]
      if item && @battle.pbRegisterItem(@user.index, item, target)
        PBDebug.log_ai("=> will use item #{item} (KO race item choice)")
        PBDebug.log("")
        return
      end
  end

  #---------------------------------------------------------------------------
  # KO Race Decision System
  #---------------------------------------------------------------------------
  def pbGetKORaceChoice
    summary = matchup_summary

    # Step 1: If we can win KO race with raw damage, use best damage move
    if summary[:any_damage_wins] && summary[:best_ko_race_move]
      move = summary[:best_ko_race_move]
      target = summary[:best_ko_race_target]
      PBDebug.log_ai("[KO Race] Damage wins available, using #{move.name}")
      return { type: :damage, move: move, target: target }
    end

    # Step 2: If setup leads to winning KO race, use setup move
    if summary[:any_setup_wins] && summary[:best_ko_race_setup]
      setup_move = summary[:best_ko_race_setup]
      # Verify setup is safe (foe can't OHKO during setup)
      unless summary[:foe_can_ohko]
        PBDebug.log_ai("[KO Race] Setup wins available, using #{setup_move.name}")
        return { type: :setup, move: setup_move, target: -1 }
      else
        PBDebug.log_ai("[KO Race] Setup wins but foe can OHKO, skipping setup")
      end
    end
  end

  #---------------------------------------------------------------------------
  # Evaluate item use
  # Returns { item: Symbol, target: Integer, score: Integer } or nil
  #---------------------------------------------------------------------------
  def evaluate_item_use
    return nil unless @trainer.has_skill_flag?("UseItems")

    items = @battle.pbGetOwnerItems(@user.index)
    return nil if items.nil? || items.empty?

    best_item = nil
    best_score = MOVE_BASE_SCORE  # Item must score above base to be considered
    best_target = nil

    items.each do |item|
      next unless @battle.pbCanUseItemOnPokemon?(item, @user.battler.pokemon, @user.battler, nil)

      # Score the item using existing handlers
      score = MOVE_BASE_SCORE
      # Apply general item score modifiers (inventory count, successive use, etc.)
      score = Battle::AI::Handlers.apply_general_item_score_modifiers(
        score, item, @user.battler.pokemonIndex, nil, self, @battle
      )
      # Apply item-specific effect scores
      score = Battle::AI::Handlers.item_score(item, score, @user.battler.pokemonIndex, nil, self, @battle)

      if score > best_score
        best_score = score
        best_item = item
        best_target = @user.battler.pokemonIndex
      end
    end

    return nil unless best_item
    return { item: best_item, target: best_target, score: best_score }
  end

  #---------------------------------------------------------------------------
  # Compute active battle contexts for context-based decision making
  # Returns array of contexts in priority order
  #---------------------------------------------------------------------------
  def compute_battle_contexts(foe)
    contexts = [:win_ko_race]  # Always primary goal

    foe_side = foe.pbOwnSide
    screen_turns = [
      foe_side.effects[PBEffects::Reflect] || 0,
      foe_side.effects[PBEffects::LightScreen] || 0,
      foe_side.effects[PBEffects::AuroraVeil] || 0
    ].max

    contexts << :stall_screens if screen_turns > 0
    contexts << :deal_chip_damage  # Always a fallback

    contexts
  end

  #---------------------------------------------------------------------------
  # Evaluate outcomes for a given context
  # Returns best outcome hash for given context, or nil if none satisfy
  #---------------------------------------------------------------------------
  def evaluate_outcomes_for_context(outcomes, context, battle_state)
    case context
    when :win_ko_race
      winners = outcomes.select { |_, o| o[:result] == :user_wins }
      return nil if winners.empty?
      # Return fastest win
      best = winners.min_by { |_, o| o[:turns] }
      best ? best.last : nil
    when :stall_screens
      screen_turns = battle_state[:screen_turns] || 0
      return nil if screen_turns == 0
      stallers = outcomes.select { |_, o| o[:turns] >= screen_turns }
      return nil if stallers.empty?
      # Return highest damage dealt among stallers
      best = stallers.max_by { |_, o| o[:user_dmg_dealt] }
      best ? best.last : nil
    when :deal_chip_damage
      # Return outcome with highest user damage dealt
      best = outcomes.max_by { |_, o| o[:user_dmg_dealt] }
      best ? best.last : nil
    else
      nil
    end
  end

  #---------------------------------------------------------------------------
  # Simulate KO race for a reserve Pokemon against a foe
  # Creates temporary AIBattler-like interface for the reserve
  # effective_hp: Optional reduced HP to account for switch-in damage (Scenario 1)
  # Returns hash with outcome details including context-aware best result
  #---------------------------------------------------------------------------
  def simulate_ko_race_for_reserve(pkmn, foe, effective_hp: nil)
    # Default losing outcome for early returns
    default_loss = { result: :target_wins, turns: 1, user_dmg_dealt: 0, target_dmg_dealt: pkmn&.hp || 0,
                     user_hp_remaining: 0, target_hp_remaining: foe&.hp || 0 }
    return default_loss unless pkmn && foe

    # Use provided effective_hp (after switch-in damage) or full HP
    reserve_hp = effective_hp || pkmn.hp
    return default_loss if reserve_hp <= 0

    # Create a temporary battler to simulate the reserve
    temp_battler = Battle::Battler.new(@battle, @user.index)
    temp_battler.pbInitialize(pkmn, 0)

    # Create temporary AIBattler wrapper
    temp_ai = Battle::AI::AIBattler.new(self, @user.index)
    temp_ai.refresh_battler

    # Store original battler and swap
    orig_battler = @battle.battlers[@user.index]
    @battle.battlers[@user.index] = temp_battler

    begin
      # Pre-compute battle contexts
      contexts = compute_battle_contexts(foe)

      # Build battle state for context evaluation
      foe_side = foe.pbOwnSide
      battle_state = {
        screen_turns: [
          foe_side.effects[PBEffects::Reflect] || 0,
          foe_side.effects[PBEffects::LightScreen] || 0,
          foe_side.effects[PBEffects::AuroraVeil] || 0
        ].max
      }

      # Simulate all damaging moves and store outcomes
      outcomes = {}
      pkmn.moves.each do |move|
        next unless move
        next if move.power == 0 || (move.pp == 0 && move.total_pp > 0)

        sim_move = Battle::Move.from_pokemon_move(@battle, move)
        ai_move = Battle::AI::AIMove.new(self)
        ai_move.set_up(sim_move)

        # Simulate damage
        predicted_dmg = ai_move.predicted_damage(user: temp_ai, target: foe, user_pokemon: pkmn)
        next if predicted_dmg <= 0

        # Get foe's damage against reserve
        foe_best = best_damage_move_against(foe, temp_ai)
        foe_dmg = foe_best[:dmg]

        # Speed comparison
        user_speed = pkmn.speed
        target_speed = foe.rough_stat(:SPEED)
        user_first = user_speed > target_speed

        # Full KO race simulation
        user_hp = reserve_hp
        target_hp = foe.hp
        turns = 0
        max_turns = 20
        user_dmg_dealt = 0
        target_dmg_dealt = 0

        while turns < max_turns && user_hp > 0 && target_hp > 0
          turns += 1

          if user_first
            target_hp -= predicted_dmg
            user_dmg_dealt += predicted_dmg
            break if target_hp <= 0

            user_hp -= foe_dmg
            target_dmg_dealt += foe_dmg
          else
            user_hp -= foe_dmg
            target_dmg_dealt += foe_dmg
            break if user_hp <= 0

            target_hp -= predicted_dmg
            user_dmg_dealt += predicted_dmg
          end
        end

        result = target_hp <= 0 ? :user_wins : :target_wins
        outcomes[move.id] = {
          result: result,
          turns: turns,
          user_dmg_dealt: user_dmg_dealt,
          target_dmg_dealt: target_dmg_dealt,
          user_hp_remaining: [user_hp, 0].max,
          target_hp_remaining: [target_hp, 0].max
        }
      end

      # If no valid moves, return default loss
      return default_loss if outcomes.empty?

      # Iterate contexts in priority order, find first satisfying outcome
      contexts.each do |context|
        best_outcome = evaluate_outcomes_for_context(outcomes, context, battle_state)
        if best_outcome
          PBDebug.log_ai("[KO Race Context] #{pkmn.name} vs #{foe.name}: context=#{context}, result=#{best_outcome[:result]}, turns=#{best_outcome[:turns]}, user_dmg=#{best_outcome[:user_dmg_dealt]}")
          return best_outcome
        end
      end

      # Fallback: return outcome with highest damage dealt
      best_fallback = outcomes.max_by { |_, o| o[:user_dmg_dealt] }
      best_fallback ? best_fallback.last : default_loss
    ensure
      # Restore original battler
      @battle.battlers[@user.index] = orig_battler
    end
  end

  #---------------------------------------------------------------------------
  # Get current battler's KO race outcome vs a foe from cached matchup_summary
  # Returns outcome hash or nil if unavailable
  #---------------------------------------------------------------------------
  def get_current_battler_outcome(foe)
    summary = matchup_summary
    foe_entry = summary[:foes][foe.index]
    return nil unless foe_entry

    {
      result: foe_entry[:damage_wins] ? :user_wins : :target_wins,
      turns: foe_entry[:ko_race_turns] || 999,
      user_dmg_dealt: foe_entry[:user_best_dmg] || 0,
      user_hp_remaining: foe_entry[:damage_wins] ? @user.hp : 0,
      target_hp_remaining: foe_entry[:damage_wins] ? 0 : foe.hp
    }
  end

  #---------------------------------------------------------------------------
  # Calculate total switch-in damage for a reserve (hazards + first-hit)
  # Accounts for command phase vs faint replacement scenarios
  #---------------------------------------------------------------------------
  def calculate_switch_in_damage(pkmn, foe)
    entry_dmg = calculate_entry_hazard_damage(pkmn, @user.index & 1)

    # Scenario detection:
    # - Scenario 1: Command phase, foe hasn't acted → first-hit applies
    # - Scenario 2: Command phase, foe already acted → no first-hit
    # - Scenario 3: Faint replacement → first-hit applies (foe gets fresh turn)
    faint_replacement = !@battle.command_phase
    foe_already_acted = @battle.command_phase && foe.battler.movedThisRound?
    first_hit_applies = faint_replacement || !foe_already_acted

    first_hit_dmg = 0
    if first_hit_applies
      # Get foe's worst move vs this reserve
      known_damaging = known_foe_moves(foe).select { |m| m&.damagingMove? }
      worst_damage = 0
      worst_move_id = nil
      known_damaging.each do |m|
        sim_move = Battle::Move.from_pokemon_move(@battle, Pokemon::Move.new(m.id))
        target = Battle::AI::AIBattler.new(self, @user.index)
        ai_move = Battle::AI::AIMove.new(self)
        ai_move.set_up(sim_move)
        dmg = ai_move.predicted_damage(user: foe, target: target, target_pokemon: pkmn)
        if dmg > worst_damage
          worst_damage = dmg
          worst_move_id = m.id
        end
      end

      # For Scenario 1 (command phase, foe hasn't acted): apply prediction roll
      scenario_1 = @battle.command_phase && !foe_already_acted && !@user.battler.fainted?
      if scenario_1 && worst_move_id
        # Get foe's worst move vs current battler
        foe_vs_current = damage_moves(foe, @user)
        best_vs_current = foe_vs_current.values.max_by { |md| md[:dmg] }

        if best_vs_current && best_vs_current[:dmg] > 0
          move_C_id = best_vs_current[:move].id   # worst move vs current
          move_R_id = worst_move_id                # worst move vs replacement

          if move_C_id == move_R_id
            # Same move is worst for both — no prediction needed
            first_hit_dmg = worst_damage
          else
            # Different worst moves — compute prediction probability
            dmg_A = best_vs_current[:dmg]
            move_R_vs_current = foe_vs_current[move_R_id]
            dmg_B = move_R_vs_current ? move_R_vs_current[:dmg] : 0

            ratio = dmg_B.to_f / [dmg_A, 1].max
            chance = 1.0 - 0.8 * (ratio ** 3)
            chance = [[chance, 0.2].max, 1.0].min

            summary = matchup_summary
            roll = summary[:foes][foe.index][:switch_prediction_roll]

            if roll < (chance * 100).to_i
              # Foe uses move_C (targeting current) — simulate on replacement
              sim_move = Battle::Move.from_pokemon_move(@battle, Pokemon::Move.new(move_C_id))
              target = Battle::AI::AIBattler.new(self, @user.index)
              ai_move = Battle::AI::AIMove.new(self)
              ai_move.set_up(sim_move)
              first_hit_dmg = ai_move.predicted_damage(user: foe, target: target, target_pokemon: pkmn)
            else
              # Foe predicted the switch — uses move_R
              first_hit_dmg = worst_damage
            end
          end
        else
          first_hit_dmg = worst_damage
        end
      else
        # Scenarios 2 & 3 or no prediction needed
        first_hit_dmg = worst_damage
      end
    end

    entry_dmg + first_hit_dmg
  end

  #---------------------------------------------------------------------------
  # Find the best battler (current or reserve) for the current context
  # Returns :current, party index, or nil
  #---------------------------------------------------------------------------
  def find_best_battler_for_context(foe, forced_switch: false)
    contexts = compute_battle_contexts(foe)
    foe_side = foe.pbOwnSide
    battle_state = {
      screen_turns: [
        foe_side.effects[PBEffects::Reflect] || 0,
        foe_side.effects[PBEffects::LightScreen] || 0,
        foe_side.effects[PBEffects::AuroraVeil] || 0
      ].max
    }

    # Gather all candidate outcomes: { :current => outcome, pkmn_index => outcome, ... }
    candidates = {}

    # Current battler's outcome (skip if forced switch from faint)
    unless @user.battler.fainted?
      current_outcome = get_current_battler_outcome(foe)
      candidates[:current] = current_outcome if current_outcome
    end

    # Each reserve's outcome (with survival check)
    party = @battle.pbParty(@user.index)
    party.each_with_index do |pkmn, idx|
      next unless pkmn && pkmn.able? && !pkmn.egg?
      next if @battle.pbFindBattler(idx, @user.index)  # Skip if already in battle

      # Calculate effective HP (entry hazards + first-hit based on scenario)
      switch_in_dmg = calculate_switch_in_damage(pkmn, foe)
      effective_hp = pkmn.hp - switch_in_dmg
      next if effective_hp <= 0  # Dies on entry

      # Get reserve's outcome (KO race already accounts for speed/priority)
      reserve_outcome = simulate_ko_race_for_reserve(pkmn, foe, effective_hp: effective_hp)
      candidates[idx] = reserve_outcome
    end

    return nil if candidates.empty?

    # Rank all candidates by context priority
    # Make a copy of candidates for iteration
    remaining = candidates.dup
    ranked = []
    contexts.each do |context|
      best = evaluate_outcomes_for_context(remaining, context, battle_state)
      if best
        remaining.each do |key, outcome|
          if outcome == best
            ranked << key unless ranked.include?(key)
            remaining.delete(key)  # Remove so we can find second-best
            break
          end
        end
      end
    end
    # Add remaining candidates at end
    remaining.keys.each { |k| ranked << k unless ranked.include?(k) }

    # Return best choice
    if forced_switch
      # Skip :current if present, return best reserve
      ranked.reject { |k| k == :current }.first
    else
      ranked.first
    end
  end

  #override choose move - remove turn count limit
  def pbChooseMove(choices)
    user_battler = @user.battler
    max_score = choices.map { |c| c[1] }.max || 0
    if @trainer.high_skill? && @user.can_switch_lax?
      if max_score < MOVE_BASE_SCORE - 20
        move_scores = choices.map { |c| "#{c[4].name}=#{c[1]}" }.join(", ")
        PBDebug.log_ai("#{@user.name} wants to switch due to terrible moves [#{move_scores}]")
        if pbChooseToSwitchOut(true)
          @battle.pbUnregisterMegaEvolution(@user.index)
          return
        end
        PBDebug.log_ai("#{@user.name} won't switch after all")
      end
    end

    if choices.length == 0
      @battle.pbAutoChooseMove(user_battler.index)
      PBDebug.log_ai("#{@user.name} will auto-use a move or Struggle")
      return
    end

    threshold = max_score - 20
    choices.each { |c| c[3] = [c[1] - threshold, 0].max }
    total_score = choices.sum { |c| c[3] }
    PBDebug.log_ai("Move choices for #{@user.name} with threshold: #{threshold}: ")
    choices.each_with_index do |c, i|
      chance = sprintf("%5.1f", (c[3] > 0) ? 100.0 * c[3] / total_score : 0)
      log_msg = "   * #{chance}% to use #{c[4].name}"
      log_msg += " (target #{c[2]})" if c[2] >= 0
      log_msg += ": score #{c[1]}"
      PBDebug.log_ai(log_msg)
    end
    randNum = pbAIRandom(total_score)
    choices.each do |c|
      randNum -= c[3]
      next if randNum >= 0
      pbRegisterEnemySpecialActionFromMove(user_battler, c[4])
      @battle.pbRegisterMove(user_battler.index, c[0], false)
      @battle.pbRegisterTarget(user_battler.index, c[2]) if c[2] && c[2] >= 0
      break
    end
    if @battle.choices[user_battler.index][2]
      move_name = @battle.choices[user_battler.index][2].name
      if @battle.choices[user_battler.index][3] >= 0
        PBDebug.log_ai("=> will use #{move_name} (target #{@battle.choices[user_battler.index][3]})")
      else
        PBDebug.log_ai("=> will use #{move_name}")
      end
    end
    PBDebug.flush
  end

  #override pbChooseToSwitchOut
  def pbChooseToSwitchOut(terrible_moves = false, skip_should_switch: false)
    return false if !@battle.canSwitch   # Battle rule
    return false if @user.wild?
    return false if !@battle.pbCanSwitchOut?(@user.index)
    # Don't switch if all foes are unable to do anything, e.g. resting after
    # Hyper Beam, will Truant (i.e. free turn)
    if @trainer.high_skill? && !terrible_moves
      foe_can_act = false
      each_foe_battler(@user.side) do |b, i|
        next if !b.can_attack?
        foe_can_act = true
        break
      end
      return false if !foe_can_act
    end
    # Various calculations to decide whether to switch
    if terrible_moves
      PBDebug.log_ai("#{@user.name} is being forced to switch out")
    elsif skip_should_switch
      PBDebug.log_ai("#{@user.name} is considering switch (skipping ShouldSwitch handlers)")
    else
      return false if !@trainer.has_skill_flag?("ConsiderSwitching")
      reserves = get_non_active_party_pokemon(@user.index)
      return false if reserves.empty?
      should_switch = Battle::AI::Handlers.should_switch?(@user, reserves, self, @battle)
      if should_switch && @trainer.medium_skill?
        should_switch = false if Battle::AI::Handlers.should_not_switch?(@user, reserves, self, @battle)
      end
      return false if !should_switch
    end
    # Want to switch; find the best replacement Pokémon
    idxParty = choose_best_replacement_pokemon(@user.index, false, terrible_moves)
    if idxParty < 0   # No good replacement Pokémon found
      PBDebug.log_ai("   => no good replacement Pokémon, will not switch after all")
      return false
    end
    # Prefer using Baton Pass instead of switching
    baton_pass = -1
    @user.battler.eachMoveWithIndex do |m, i|
      next if m.function_code != "SwitchOutUserPassOnEffects"   # Baton Pass
      next if !@battle.pbCanChooseMove?(@user.index, i, false)
      baton_pass = i
      break
    end
    if baton_pass >= 0 && @battle.pbRegisterMove(@user.index, baton_pass, false)
      PBDebug.log_ai("=> will use Baton Pass to switch out")
      return true
    elsif @battle.pbRegisterSwitch(@user.index, idxParty)
      PBDebug.log_ai("=> will switch with #{@battle.pbParty(@user.index)[idxParty].name}")
      return true
    end
    return false
  end

  def choose_best_replacement_pokemon(idxBattler, forced_switch = false, terrible_moves = false)
    # forced_switch: Passed as true explicitly by the battle engine when a Pokémon faints or uses a pivoting move (e.g., U-turn, Parting Shot).
    # terrible_moves: Passed as true during the AI's action phase if its current moveset has no good options.

    # Clear caches only on forced switches (faints/pivots) where a different
    # Pokémon now occupies the battler index, invalidating cached results.
    if forced_switch
      @_ai_dmg_cache = {}
      @_matchup_cache = {}
    end

    # Get all possible replacement Pokémon
    party = @battle.pbParty(idxBattler)
    reserves = []
    party.each_with_index do |_pkmn, i|
      next if !@battle.pbCanSwitchIn?(idxBattler, i)
      if !terrible_moves && !forced_switch   # Choosing an action for the round
        ally_will_switch_with_i = false
        @battle.allSameSideBattlers(idxBattler).each do |b|
          next if @battle.choices[b.index][0] != :SwitchOut || @battle.choices[b.index][1] != i
          ally_will_switch_with_i = true
          break
        end
        next if ally_will_switch_with_i
      end

      reserves.push([i, 100])
      break if @trainer.has_skill_flag?("UsePokemonInOrder") && reserves.length > 0
    end
    return -1 if reserves.length == 0

    # Double KO: all opposing battlers are either fainted OR just sent in as
    # replacements (turnCount == 0 mid-battle), meaning we shouldn't know what
    # the player chose — pick randomly instead of scoring against them.
    if forced_switch
      foe_is_unknown = true
      @battle.allOtherSideBattlers(idxBattler).each do |b|
        # Foe is "known" if they have had at least one turn in battle
        # (turnCount > 0 means they've been active before, so not a fresh replacement)
        if !b.fainted? && b.turnCount > 0
          foe_is_unknown = false
          break
        end
      end
      if foe_is_unknown
        chosen = reserves.sample
        PBDebug.log_ai("=> double KO: randomly choosing #{party[chosen[0]].name}")
        return chosen[0]
      end
    end

    # Use unified context-based selection
    best_choice = nil
    each_foe_battler(@user.side) do |foe, _|
      choice = find_best_battler_for_context(foe, forced_switch: forced_switch || terrible_moves)

      if choice && choice != :current
        best_choice = choice
        PBDebug.log_ai("[Switch] Best battler vs #{foe.name}: party[#{choice}] (#{party[choice].name})")
        break  # Found a reserve that beats current
      elsif choice == :current && !forced_switch && !terrible_moves
        PBDebug.log_ai("[Switch] Current battler is best vs #{foe.name}, not switching")
        return -1
      end
    end

    if best_choice
      PBDebug.log_ai("=> switching to #{party[best_choice].name}")
      return best_choice
    end

    # Fallback for forced switch: pick first available reserve
    if forced_switch || terrible_moves
      party.each_with_index do |pkmn, idx|
        next unless pkmn && pkmn.able? && !pkmn.egg?
        next if @battle.pbFindBattler(idx, idxBattler)
        PBDebug.log_ai("=> forced switch fallback: sacking #{pkmn.name}")
        return idx
      end
    end

    PBDebug.log_ai("=> no good replacement found, staying in")
    return -1
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
  # For high_skill trainers, also includes KO race simulation results.
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

      # KO race simulation results (high_skill only)
      summary[:any_damage_wins] = false
      summary[:any_setup_wins] = false
      summary[:best_ko_race_move] = nil
      summary[:best_ko_race_setup] = nil
      summary[:best_ko_race_target] = nil

      # Pre-collect setup and damage moves for KO race simulation
      user_setup_moves = @trainer.high_skill? ? get_setup_moves(@user) : []
      user_damage_moves = @trainer.high_skill? ? get_damage_moves(@user) : []

      each_foe_battler(@user.side) do |b, _i|
        foe_dmg_data = damage_moves(b, @user)
        user_dmg_data = damage_moves(@user, b)

        best_foe = foe_dmg_data.values.max_by { |md| md[:dmg] }
        best_user = user_dmg_data.values.max_by { |md| md[:dmg] }

        foe_speed = b.rough_stat(:SPEED)
        foe_best_dmg = best_foe ? best_foe[:dmg] : 0
        user_best_dmg = best_user ? best_user[:dmg] : 0

        foe_outspeeds = foe_speed > user_speed
        foe_has_priority = best_foe && best_foe[:move].priority > 0
        foe_effectively_outspeeds = foe_outspeeds || foe_has_priority

        foe_entry = {
          best_dmg:    foe_best_dmg,
          best_move:   best_foe&.dig(:move),
          best_priority: best_foe ? best_foe[:move].priority : 0,
          user_best_dmg: user_best_dmg,
          user_best_move: best_user&.dig(:move),
          speed:       foe_speed,
          outspeeds:   foe_outspeeds,
          effectively_outspeeds: foe_effectively_outspeeds,
          can_ohko:    foe_best_dmg >= @user.hp,
          dmg_ratio:   foe_best_dmg.to_f / [@user.battler.totalhp, 1].max,
          foe_hp:      b.hp,
          foe_totalhp: b.battler.totalhp,

          # KO race simulation results (high_skill only)
          damage_wins: false,
          setup_wins: false,
          best_damage_move: nil,
          best_setup_move: nil,
          ko_race_turns: nil,
        }
        foe_entry[:switch_prediction_roll] = pbAIRandom(100)

        # KO race simulation for high_skill trainers
        if @trainer.high_skill?
          # Test each damage move in a KO race
          best_damage_turns = 999
          user_damage_moves.each do |move|
            # Get cached damage for consistency (ensures same crit roll as damage_moves cache)
            cached_dmg = user_dmg_data[move.id]&.dig(:dmg) || 0
            next if cached_dmg <= 0
            ko_result = simulate_ko_race(@user, b, move, cached_user_dmg: cached_dmg)
            if ko_result[:result] == :user_wins
              # Use turns from simulation result
              turns = ko_result[:turns]
              if !foe_entry[:damage_wins] || turns < best_damage_turns
                foe_entry[:damage_wins] = true
                foe_entry[:best_damage_move] = move
                foe_entry[:ko_race_turns] = turns
                best_damage_turns = turns
                PBDebug.log_ai("[KO Race] #{@user.name} wins vs #{b.name} with #{move.name} (#{turns} turns)")
              end
            end
          end

          # Test setup → attack combinations (skip if Unaware)
          unless b.has_active_ability?(:UNAWARE) && !has_mold_breaker?(@user)
            best_setup_turns = 999
            user_setup_moves.each do |setup_move|
              user_damage_moves.each do |attack_move|
                # Get cached damage for consistency
                cached_dmg = user_dmg_data[attack_move.id]&.dig(:dmg) || 0
                next if cached_dmg <= 0
                ko_result = simulate_ko_race(@user, b, attack_move, setup_move: setup_move, cached_user_dmg: cached_dmg)
                if ko_result[:result] == :user_wins
                  # Use turns from simulation result (already includes setup turn)
                  turns = ko_result[:turns]
                  if !foe_entry[:setup_wins] || turns < best_setup_turns
                    foe_entry[:setup_wins] = true
                    foe_entry[:best_setup_move] = setup_move
                    foe_entry[:best_damage_move] ||= attack_move
                    best_setup_turns = turns
                    PBDebug.log_ai("[KO Race] #{@user.name} wins vs #{b.name} with #{setup_move.name} → #{attack_move.name} (#{turns} turns)")
                  end
                end
              end
            end
          end

          # Update summary-level flags
          if foe_entry[:damage_wins]
            if !summary[:any_damage_wins] || (foe_entry[:ko_race_turns] || 999) < (summary[:best_ko_race_turns] || 999)
              summary[:any_damage_wins] = true
              summary[:best_ko_race_move] = foe_entry[:best_damage_move]
              summary[:best_ko_race_target] = b.index
              summary[:best_ko_race_turns] = foe_entry[:ko_race_turns]
            end
          end
          if foe_entry[:setup_wins] && !foe_entry[:damage_wins]
            # Only track setup wins if we can't win with raw damage
            if !summary[:any_setup_wins]
              summary[:any_setup_wins] = true
              summary[:best_ko_race_setup] = foe_entry[:best_setup_move]
              summary[:best_ko_race_move] ||= foe_entry[:best_damage_move]
              summary[:best_ko_race_target] ||= b.index
            end
          end
        end

        summary[:foes][b.index] = foe_entry
        summary[:max_foe_dmg] = [summary[:max_foe_dmg], foe_best_dmg].max
        summary[:foe_can_ohko] = true if foe_entry[:can_ohko]
        summary[:foe_can_ohko_and_outspeeds] = true if foe_entry[:can_ohko] && foe_effectively_outspeeds
        summary[:user_can_ko_any] = true if user_best_dmg >= b.hp
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

#===============================================================================
# AIBattler compatibility patch (prevent NoMethodError)
#===============================================================================
class Battle::AI::AIBattler
  def unstoppableAbility?(ability_id)
    return self.battler.unstoppableAbility?(ability_id) if self.battler.respond_to?(:unstoppableAbility?)
    return false
  end

  def isRaidBoss?
    return self.battler.isRaidBoss? if self.battler.respond_to?(:isRaidBoss?)
    return false
  end

  #=============================================================================
  # Scenario-based Tera scoring using predicted damage and 1v1 simulation
  #=============================================================================
  alias total_tera_score_original get_total_tera_score
  def get_total_tera_score
    tera_type = @battler.tera_type
    type_name = GameData::Type.get(tera_type).name
    PBDebug.log_ai("#{self.name} is considering Terastallizing into the #{type_name}-type...")
    @ai.instance_variable_set(:@_computing_tera_score, true)
    begin
      score = -10  # tera is a limited resource, needs justification
      PBDebug.log_ai("[Tera] Starting score: #{score} (base cost)")
      @ai.each_foe_battler(@side) do |b, _i|
        foe_score = compute_tera_score_vs_foe(b)
        PBDebug.log_ai("[Tera] vs #{b.name}: #{foe_score > 0 ? '+' : ''}#{foe_score}")
        score += foe_score
      end
      context = get_tera_context_bonus(tera_type)
      PBDebug.log_ai("[Tera] Context bonus: #{context > 0 ? '+' : ''}#{context}") if context != 0
      score += context
      PBDebug.log_ai("[Tera] Final score: #{score}")
      return score
    ensure
      @ai.instance_variable_set(:@_computing_tera_score, false)
    end
  end

  #---------------------------------------------------------------------------
  # Per-foe scenario scoring
  #---------------------------------------------------------------------------
  def compute_tera_score_vs_foe(foe)
    # --- Gather damage data WITHOUT tera ---
    user_dmg_no_tera = @ai.damage_moves(self, foe)
    foe_dmg_no_tera  = @ai.damage_moves(foe, self)

    best_user_no_tera = user_dmg_no_tera.values.max_by { |md| md[:dmg] }
    best_foe_no_tera  = foe_dmg_no_tera.values.max_by { |md| md[:dmg] }

    u_dmg_no  = best_user_no_tera ? best_user_no_tera[:dmg] : 0
    f_dmg_no  = best_foe_no_tera  ? best_foe_no_tera[:dmg]  : 0
    foe_chosen_move_id = best_foe_no_tera ? best_foe_no_tera[:move].id : nil

    # --- Temporarily simulate tera on self to get "with tera" damage ---
    prev_tera = @battler.pokemon.instance_variable_get(:@terastallized)
    prev_form = @battler.form
    begin
      @battler.pokemon.instance_variable_set(:@terastallized, true)
      @battler.form = @battler.pokemon.form if @battler.form != @battler.pokemon.form
      @battler.pbUpdate(true)

      user_dmg_with_tera = @ai.damage_moves(self, foe)
      foe_dmg_with_tera  = @ai.damage_moves(foe, self)
    ensure
      @battler.pokemon.instance_variable_set(:@terastallized, prev_tera)
      @battler.form = prev_form
      @battler.pbUpdate(true)
    end

    best_user_with_tera = user_dmg_with_tera.values.max_by { |md| md[:dmg] }
    u_dmg_tera = best_user_with_tera ? best_user_with_tera[:dmg] : 0

    # Foe damage with tera: use the SAME move the foe would choose pre-tera
    if foe_chosen_move_id && foe_dmg_with_tera[foe_chosen_move_id]
      f_dmg_tera = foe_dmg_with_tera[foe_chosen_move_id][:dmg]
    else
      # Foe has no damaging moves or move not found — use 0
      f_dmg_tera = 0
    end

    # --- Speed / priority ---
    user_speed = self.rough_stat(:SPEED)
    foe_speed  = foe.rough_stat(:SPEED)
    best_user_move_priority = best_user_no_tera ? best_user_no_tera[:move].priority : 0
    best_user_tera_priority = best_user_with_tera ? best_user_with_tera[:move].priority : 0
    user_priority = [best_user_move_priority, best_user_tera_priority].max
    foe_priority  = best_foe_no_tera ? best_foe_no_tera[:move].priority : 0

    if user_priority > foe_priority
      user_outspeeds = true
    elsif foe_priority > user_priority
      user_outspeeds = false
    else
      user_outspeeds = user_speed >= foe_speed
    end

    PBDebug.log_ai("[Tera]   u_dmg=#{u_dmg_no}/#{u_dmg_tera} f_dmg=#{f_dmg_no}/#{f_dmg_tera} " \
                   "spd=#{user_outspeeds ? 'user' : 'foe'} foe_hp=#{foe.hp} user_hp=#{self.hp}")

    # --- Scenario 1: User outspeeds + KOs without tera ---
    if user_outspeeds && u_dmg_no >= foe.hp
      PBDebug.log_ai("[Tera]   Scenario 1: can KO without tera, skip")
      return -30
    end

    # --- Scenario 2: User outspeeds + KOs only WITH tera ---
    if user_outspeeds && u_dmg_no < foe.hp && u_dmg_tera >= foe.hp
      PBDebug.log_ai("[Tera]   Scenario 2: tera enables KO")
      return 50
    end

    # --- Scenario 3: Everything else → 1v1 simulation ---
    return simulate_1v1_tera_value(
      u_dmg_no, u_dmg_tera, f_dmg_no, f_dmg_tera,
      foe.hp, self.hp, user_outspeeds
    )
  end

  #---------------------------------------------------------------------------
  # Turns-to-KO comparison: with and without tera
  #---------------------------------------------------------------------------
  def simulate_1v1_tera_value(u_dmg_no, u_dmg_tera, f_dmg_no, f_dmg_tera,
                              foe_hp, user_hp, user_outspeeds)
    # Turns to KO in each direction
    u_turns_no   = u_dmg_no   > 0 ? (foe_hp.to_f  / u_dmg_no).ceil   : 999
    u_turns_tera = u_dmg_tera > 0 ? (foe_hp.to_f  / u_dmg_tera).ceil : 999
    f_turns_no   = f_dmg_no   > 0 ? (user_hp.to_f / f_dmg_no).ceil   : 999
    f_turns_tera = f_dmg_tera > 0 ? (user_hp.to_f / f_dmg_tera).ceil : 999

    # Who wins? If user outspeeds, user wins ties (acts first)
    if user_outspeeds
      win_no   = u_turns_no   <= f_turns_no
      win_tera = u_turns_tera <= f_turns_tera
    else
      win_no   = u_turns_no   < f_turns_no
      win_tera = u_turns_tera < f_turns_tera
    end

    PBDebug.log_ai("[Tera]   1v1: u_turns=#{u_turns_no}/#{u_turns_tera} f_turns=#{f_turns_no}/#{f_turns_tera} " \
                   "win_no=#{win_no} win_tera=#{win_tera}")

    # Tera flips losing → winning
    if !win_no && win_tera
      PBDebug.log_ai("[Tera]   Scenario 3a: tera flips losing matchup → winning")
      return 60
    end

    # Tera makes winning → losing
    if win_no && !win_tera
      PBDebug.log_ai("[Tera]   Scenario 3b: tera makes winning → losing")
      return -40
    end

    # Wins both
    if win_no && win_tera
      turns_saved = u_turns_no - u_turns_tera
      survival_gained = f_turns_tera - f_turns_no
      bonus = 0
      if turns_saved > 0 || survival_gained > 0
        bonus = [[turns_saved * 10 + survival_gained * 5, 30].min, 10].max
        PBDebug.log_ai("[Tera]   Scenario 3c: wins both, saves #{turns_saved} turns / gains #{survival_gained} survival → +#{bonus}")
      else
        bonus = -5
        PBDebug.log_ai("[Tera]   Scenario 3d: wins both, no improvement → #{bonus}")
      end
      return bonus
    end

    # Loses both
    survival_gained = f_turns_tera - f_turns_no
    if survival_gained > 0
      bonus = [[survival_gained * 5, 15].min, 5].max
      PBDebug.log_ai("[Tera]   Scenario 3e: loses both, survives longer with tera → +#{bonus}")
      return bonus
    else
      PBDebug.log_ai("[Tera]   Scenario 3f: loses both, no improvement → -10")
      return -10
    end
  end

  #---------------------------------------------------------------------------
  # Non-damage context bonuses for tera type
  #---------------------------------------------------------------------------
  def get_tera_context_bonus(tera_type)
    bonus = 0
    case tera_type
    when :FLYING
      # Immune to Spikes, Toxic Spikes, Sticky Web
      if @battler.pbOwnSide.effects[PBEffects::Spikes] > 0 ||
         @battler.pbOwnSide.effects[PBEffects::ToxicSpikes] > 0 ||
         @battler.pbOwnSide.effects[PBEffects::StickyWeb]
        bonus += 10
      end
    when :POISON, :STEEL
      # Immune to poison/toxic
      if @battler.status == :NONE
        @ai.each_foe_battler(@side) do |b, _|
          b.battler.eachMove do |m|
            if [:TOXIC, :POISONPOWDER, :TOXICSPIKES, :BANEFULBUNKER].include?(m.id) ||
               m.function_code == "PoisonTarget" || m.function_code == "BadlyPoisonTarget"
              bonus += 5
              break
            end
          end
        end
      end
    when :FIRE
      # Immune to burn
      if @battler.status == :NONE
        @ai.each_foe_battler(@side) do |b, _|
          b.battler.eachMove do |m|
            if [:WILLOWISP, :SCALD, :STEAMERUPTION].include?(m.id) ||
               m.function_code == "BurnTarget"
              bonus += 5
              break
            end
          end
        end
      end
    when :ELECTRIC
      # Immune to paralysis
      if @battler.status == :NONE
        @ai.each_foe_battler(@side) do |b, _|
          b.battler.eachMove do |m|
            if [:THUNDERWAVE, :STUNSPORE, :GLARE, :NUZZLE].include?(m.id) ||
               m.function_code == "ParalyzeTarget"
              bonus += 5
              break
            end
          end
        end
      end
    when :GHOST
      # Escape trapping
      if @battler.effects[PBEffects::Trapping] > 0 ||
         @battler.effects[PBEffects::MeanLook] > 0
        bonus += 15
      end
    when :DARK
      # Prankster immunity
      @ai.each_foe_battler(@side) do |b, _|
        if b.has_active_ability?(:PRANKSTER)
          bonus += 10
          break
        end
      end
    when :GRASS
      # Leech Seed / powder immunity
      if @battler.effects[PBEffects::LeechSeed] >= 0
        bonus += 10
      end
      @ai.each_foe_battler(@side) do |b, _|
        b.battler.eachMove do |m|
          if [:LEECHSEED, :SLEEPPOWDER, :STUNSPORE, :POISONPOWDER, :SPORE].include?(m.id) ||
             m.flags&.include?("Powder")
            bonus += 5
            break
          end
        end
      end
    end
    bonus
  end
end
