#===============================================================================
# [AI_Improved.rb] - Safe Move-Scoring AI for Pokémon Essentials v21.1
# - DBK / Doubles / Raid compatible
#===============================================================================

#===============================================================================
# Override: AI chooses actions BEFORE the player, not after.
#===============================================================================
class Battle
  def pbCommandPhase
    @command_phase = true
    @scene.pbBeginCommandPhase
    @battlers.each_with_index do |b, i|
      next if !b
      pbClearChoice(i) if pbCanShowCommands?(i)
      pbDeluxeTriggers(i, nil, "RoundStartCommand", 1 + @turnCount) if !b.fainted?
    end
    2.times { |side| pbActionCommands(side) }
    pbCommandPhaseLoop(false)   # AI chooses their actions
    if @decision != 0   # Battle ended, stop choosing actions
      @command_phase = false
      return
    end
    pbCommandPhaseLoop(true)    # Player chooses their actions
    @command_phase = false
  end
end


class Battle::Battler
  alias _tower_fog_pbProcessTurn pbProcessTurn
  def pbProcessTurn(choice, tryFlee = true)
    ret = _tower_fog_pbProcessTurn(choice, tryFlee)
    if @battle.is_simulation
      acted_this_turn = @lastRoundMoved == @battle.turnCount
      @_sim_action_turn = (acted_this_turn ? @battle.turnCount : nil)
      @_sim_action_succeeded = (acted_this_turn && !@lastMoveFailed)
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

#-------------------------------------------------------------------------------
# Lagging Tail / Full Incense constant (used by speed checks)
#-------------------------------------------------------------------------------
LAGGING_TAIL_ITEMS = [:LAGGINGTAIL, :FULLINCENSE]

#-------------------------------------------------------------------------------
# Delegate missing AIBattler methods to real battler
#-------------------------------------------------------------------------------
class Battle::AI::AIBattler
  def method_missing(method, *args, &block)
    @battler.send(method, *args, &block)
  end

  def respond_to_missing?(method, include_private = false)
    @battler.respond_to?(method, include_private)
  end
end

class Battle::AI
  MOVE_FAIL_SCORE = -999

  INTIMIDATE_IMMUNE = [:CLEARBODY, :WHITESMOKE, :FULLMETALBODY,
                       :HYPERCUTTER, :INNERFOCUS, :OBLIVIOUS,
                       :OWNTEMPO, :SCRAPPY, :GUARDDOG].freeze

  alias go_up_original_stat_raise_worthwhile? stat_raise_worthwhile?

  def stat_raise_worthwhile?(target, stat, fixed_change = false)
    return true if stat == :SPEED && target.stages[:SPEED] < 1
    return go_up_original_stat_raise_worthwhile?(target, stat, fixed_change)
  end

  # Returns the stat multiplier for a given stage (-6 to +6)
  def stat_stage_mult(stage)
    stage = stage.clamp(-6, 6)
    Battle::Battler::STAT_STAGE_MULTIPLIERS[stage + 6].to_f /
      Battle::Battler::STAT_STAGE_DIVISORS[stage + 6]
  end
  REPLACEMENT_THRESHOLD_TERRIBLE_MOVES = 80
  REPLACEMENT_THRESHOLD_SHOULD_SWITCH = 70

  #---------------------------------------------------------------------------
  # Simulate registered transforms (mega/tera/dynamax) on the AI's own battler
  # and foe mega evolutions so all AI scoring sees post-transform stats.
  # Called after pbRegisterEnemySpecialAction, restored via ensure.
  #---------------------------------------------------------------------------
  def simulate_registered_transforms(idxBattler)
    sim = { transforms: [] }
    battler = @battle.battlers[idxBattler]
    # AI's own mega
    if @battle.pbRegisteredMegaEvolution?(idxBattler) && !battler.mega?
      prev_form = battler.form
      battler.pokemon.makeMega
      battler.form = battler.pokemon.form
      battler.pbUpdate(true)
      sim[:transforms] << { battler: battler, type: :mega, prev_form: prev_form }
      PBDebug.log_ai("[simulate_transforms] Mega applied: #{battler.name}")
    end
    # AI's own tera
    if !battler.mega? &&
       @battle.pbRegisteredTerastallize?(idxBattler) && !battler.tera?
      prev_tera = battler.pokemon.instance_variable_get(:@terastallized)
      prev_form = battler.form
      battler.pokemon.terastallized = true
      battler.form = battler.pokemon.form if battler.form != battler.pokemon.form
      battler.pbUpdate(true)
      sim[:transforms] << { battler: battler, type: :tera, prev_form: prev_form, prev_tera: prev_tera }
      PBDebug.log_ai("[simulate_transforms] Tera applied: #{battler.name} (#{battler.pokemon.tera_type})")
    end
    # AI's own dynamax
    if @battle.pbRegisteredDynamax?(idxBattler) && !battler.dynamax?
      prev_form = battler.form
      battler.pokemon.makeDynamaxForm
      battler.form = battler.pokemon.form
      battler.pokemon.makeDynamax
      # Keep the previewed live battler consistent with a real Dynamax state so
      # copied battle sims don't immediately unDynamax it at end of round.
      battler.effects[PBEffects::Dynamax] = Settings::DYNAMAX_TURNS
      battler.pbUpdate(true)
      sim[:transforms] << { battler: battler, type: :dynamax, prev_form: prev_form }
      PBDebug.log_ai("[simulate_transforms] Dynamax applied: #{battler.name}")
    end
    # Foe mega evolutions
    @battle.battlers.each do |b|
      next unless b && !b.fainted? && b.opposes?(idxBattler)
      next if b.mega?
      # For foe previews, don't depend on battle registration.
      # If the foe currently has access to its Mega form via the correct
      # Mega Stone or Mega move, simulate the matchup as Mega.
      next unless b.pokemon&.hasMegaForm?
      prev_form = b.form
      b.pokemon.makeMega
      b.form = b.pokemon.form
      b.pbUpdate(true)
      sim[:transforms] << { battler: b, type: :mega, prev_form: prev_form }
      PBDebug.log_ai("[simulate_transforms] Foe Mega applied: #{b.name}")
    end
    sim
  end

  def restore_registered_transforms(sim)
    return unless sim
    sim[:transforms].reverse_each do |t|
      case t[:type]
      when :mega
        t[:battler].pokemon.makeUnmega
        t[:battler].form = t[:prev_form]
        t[:battler].pbUpdate(true)
      when :tera
        t[:battler].pokemon.terastallized = t[:prev_tera]
        t[:battler].form = t[:prev_form]
        t[:battler].pbUpdate(true)
      when :dynamax
        t[:battler].pokemon.makeUndynamaxForm
        t[:battler].form = t[:prev_form]
        t[:battler].pokemon.makeUndynamax
        t[:battler].effects[PBEffects::Dynamax] = 0
        t[:battler].pbUpdate(true)
      end
    end
  end

  def unregister_terapagos_tera_for_passive_move(idxBattler, sim = nil)
    battler = @battle.battlers[idxBattler]
    return false unless battler
    return false unless battler.isSpecies?(:TERAPAGOS)
    return false unless @battle.pbRegisteredTerastallize?(idxBattler)
    return false unless battler.hasActiveAbility?(:TERASHELL) && battler.hp == battler.totalhp

    @battle.pbUnregisterTerastallize(idxBattler)

    if sim && sim[:transforms]
      tera_idx = sim[:transforms].rindex { |t| t[:battler] == battler && t[:type] == :tera }
      if tera_idx
        tera_transform = sim[:transforms].delete_at(tera_idx)
        battler.pokemon.terastallized = tera_transform[:prev_tera]
        battler.form = tera_transform[:prev_form]
        battler.pbUpdate(true)
      end
    end

    PBDebug.log_ai("[tera rollback] #{battler.name} canceled Terastallization after choosing a non-damaging move with Tera Shell active")
    true
  end

  #---------------------------------------------------------------------------
  # Override pbPredictMoveFailureAgainstTarget to accept explicit arguments.
  # Replaces both the base Essentials and Gen 9 Pack versions.
  # Existing callers pass no args and get the same behavior as before.
  #---------------------------------------------------------------------------
  def pbPredictMoveFailureAgainstTarget(move = @move, user = @user, target = @target)
    # Move effect-specific checks
    return true if Battle::AI::Handlers.move_will_fail_against_target?(move.function_code, move, user, target, self, @battle)
    # Psychic Terrain blocks priority moves against grounded targets
    return true if @battle.field.terrain == :Psychic && target.affectedByTerrain? &&
                   target.opposes?(user) && move.rough_priority(user) > 0
    # Ability immunity (Volt Absorb, Flash Fire, Levitate, Good as Gold, etc.)
    return true if move.move.pbImmunityByAbility(user, target, false)
    # Dazzling / Queenly Majesty / Armor Tail — ally-side priority block
    if move.rough_priority(user) > 0 && target.opposes?(user)
      each_same_side_battler(target.side) do |b, _i|
        return true if b.has_active_ability?([:DAZZLING, :QUEENLYMAJESTY, :ARMORTAIL])
      end
    end
    # Commander immunity (conditional on form state)
    return true if target.has_active_ability?(:COMMANDER) && target.isCommander?
    # Type immunity
    calc_type = move.rough_type
    typeMod = move.move.pbCalcTypeMod(calc_type, user, target)
    return true if move.move.pbDamagingMove? && Effectiveness.ineffective?(typeMod)
    # Dark-type immunity to Prankster-boosted status moves
    return true if Settings::MECHANICS_GENERATION >= 7 && move.statusMove? &&
                   user.has_active_ability?(:PRANKSTER) && target.has_type?(:DARK) && target.opposes?(user)
    # Airborne immunity to Ground moves
    return true if move.damagingMove? && calc_type == :GROUND &&
                   target.airborne? && !move.move.hitsFlyingTargets?
    # Powder move immunity
    return true if move.move.powderMove? && !target.affectedByPowder?
    # Substitute blocks non-ignoring status moves
    return true if target.effects[PBEffects::Substitute] > 0 && move.statusMove? &&
                   !move.move.ignoresSubstitute?(user) && user.index != target.index
    return false
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
    target_data = @move.pbTarget(@user)
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

  # Scale a stat-change score delta by additional effect chance for damaging
  # moves with < 100% effect probability (e.g. Moonblast's 30% SpA drop).
  def scale_by_additional_effect(score, result, label)
    return result unless @move.damagingMove? && @move.move.addlEffect > 0 && @move.move.addlEffect < 100
    delta = result - score
    return result if delta == 0
    chance = @move.move.addlEffect
    chance = [chance * 2, 100].min if @user.has_active_ability?(:SERENEGRACE)
    scaled_delta = (delta * chance / 100.0).round
    PBDebug.log("     [additional effect scaling] #{label}: #{delta} * #{chance}% = #{scaled_delta}")
    score + scaled_delta
  end

  alias_method :orig_get_score_for_target_stat_drop, :get_score_for_target_stat_drop
  def get_score_for_target_stat_drop(score, target, stat_changes, whole_effect = true,
                                     fixed_change = false, ignore_contrary = false)
    result = orig_get_score_for_target_stat_drop(score, target, stat_changes, whole_effect, fixed_change, ignore_contrary)
    scale_by_additional_effect(score, result, "stat drop")
  end

  alias_method :orig_get_score_for_target_stat_raise, :get_score_for_target_stat_raise
  def get_score_for_target_stat_raise(score, target, stat_changes, whole_effect = true,
                                      fixed_change = false, ignore_contrary = false)
    result = orig_get_score_for_target_stat_raise(score, target, stat_changes, whole_effect, fixed_change, ignore_contrary)
    scale_by_additional_effect(score, result, "stat raise")
  end

  # Override: Returns whether the move will definitely fail (assuming no battle conditions
  # change between now and using the move).
  def pbPredictMoveFailure
    # User is awake and can't use moves that are only usable when asleep
    return true if !@user.asleep? && @move.move.usableWhenAsleep?

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

  def safe_function_code(move)
    return nil if !move || !move.respond_to?(:function_code)
    return move.function_code
  end

  def move_is_setup?(move, battler = nil)
    return false if !move
    fc = safe_function_code(move) || ""
    return false if fc.empty?
    return false if fc == "CurseTargetOrLowerUserSpd1RaiseUserAtkDef1" &&
                    battler&.has_type?(:GHOST)

    return true if fc.match?(/RaiseUser(?:Side)?/)
    return true if fc == "UserAddStockpileRaiseDefSpDef1"

    return false unless move.respond_to?(:move) && move.move.respond_to?(:statUp)
    stat_up = move.move.statUp
    return false if !stat_up || stat_up.empty?
    return false if move.damagingMove? && (real_move.addlEffect != 100 && real_move.addlEffect != 0)

    stat_up.each_slice(2).any? do |stat, stages|
      next false if !stat || !stages || stages <= 0
      [:ATTACK, :DEFENSE, :SPECIAL_ATTACK, :SPECIAL_DEFENSE,
       :SPEED, :ACCURACY, :EVASION].include?(stat)
    end
  end

  def battler_has_setup_move?(battler)
    return false if !battler
    battler.check_for_move { |m| move_is_setup?(m, battler) }
  end

  def foe_has_setup_move?(user)
    any_foe_battler?(user.side) { |b, _i| battler_has_setup_move?(b) }
  end

  # Yields each foe battler and returns true if the block ever returns truthy.
  def any_foe_battler?(side)
    each_foe_battler(side) { |b, i| return true if yield(b, i) }
    false
  end

  # Returns true if any foe has an effective phazing move against the user.
  def foe_has_effective_phazing?(user, phaze_codes = ["SwitchOutTargetStatusMove"])
    sim_move = Battle::AI::AIMove.new(self)
    any_foe_battler?(user.side) do |b, _i|
      known_foe_moves(b).any? do |m|
        next false unless phaze_codes.include?(m.function_code)
        sim_move.set_up(m)
        !pbPredictMoveFailureAgainstTarget(sim_move, b, user)
      end
    end
  end

  # Sums positive stat stages on a battler. Returns integer >= 0.
  def total_positive_boosts(battler)
    total = 0
    GameData::Stat.each_battle { |s| total += battler.stages[s.id] if battler.stages[s.id] > 0 }
    total
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
    with_decision_cache do
      # show_thinking_indicator
      set_up(idxBattler)
      # 1. Special commands (Mega, Dynamax, etc.)
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
      # Simulate registered transforms so all scoring sees post-transform stats
      sim = simulate_registered_transforms(idxBattler)
      begin
        # 2. Score moves
        choices = pbGetMoveScores
        max_move_score = choices.map { |c| c[1] }.max || 0
        # 3. Try items on the current battler first if moves are mediocre.
        if max_move_score < MOVE_BASE_SCORE
          ret = false
          PBDebug.logonerr { ret = pbChooseToUseItem(:current) }
          if ret
            PBDebug.log("")
            return
          end
          PBDebug.logonerr { ret = pbChooseToSwitchOut(true, threshold: 120) }
          if ret
            PBDebug.log("")
            return
          end
        end
        # 4. Terrible moves: try switching
        if max_move_score < REPLACEMENT_THRESHOLD_TERRIBLE_MOVES
          ret = false
          PBDebug.logonerr { ret = pbChooseToSwitchOut(true, threshold: REPLACEMENT_THRESHOLD_TERRIBLE_MOVES) }
          if ret
            PBDebug.log("")
            return
          end
          PBDebug.logonerr { ret = pbChooseToUseItem(:reserve) }
          # 5. Reserve-targeted items are a last resort.
          if ret
            PBDebug.log("")
            return
          end
        end
        # 6. Choose move as normal
        pbChooseMove(choices)
        chosen_move = @battle.choices[idxBattler][2]
        # unregister tera for terapagos when terashell active
        if chosen_move && !chosen_move.damagingMove?
          unregister_terapagos_tera_for_passive_move(idxBattler, sim)
        end
        PBDebug.log("")
        pbRegisterEnemySpecialAction2(idxBattler)
      ensure
        restore_registered_transforms(sim)
      end
    ensure
      # hide_thinking_indicator
    end
  end

  def pbDefaultChooseNewEnemy(idxBattler)
    result = with_decision_cache do
      set_up(idxBattler)
      choose_best_replacement_pokemon(idxBattler, true)
    end
    register_fresh_switch_score(idxBattler, result) if result >= 0
    result
  end

  # Sucker Punch mind games: 20% chance to swap to a OHKO damaging move
  # instead, punishing players who predict priority and use status moves.
  def try_sucker_punch_mindgame(choices, user_battler)
    chosen_move = @battle.choices[user_battler.index][2]
    return unless chosen_move
    PBDebug.log_ai("[Sucker Punch mind game] chosen=#{chosen_move.class} (#{chosen_move.name})")
    return unless chosen_move.is_a?(Battle::Move::FailsIfTargetActed)
    roll = pbAIRandom(100)
    PBDebug.log_ai("[Sucker Punch mind game] roll=#{roll} (need <30)")
    return unless roll < 30
    target_idx = @battle.choices[user_battler.index][3]
    return unless target_idx >= 0
    foe = @battlers[target_idx]
    return unless foe
    best_alt = nil
    choices.each do |c|
      next if c[4].is_a?(Battle::Move::FailsIfTargetActed)
      next unless c[4].damagingMove?
      next unless c[2] == target_idx
      best_alt = c if best_alt.nil? || c[1] > best_alt[1]
    end
    return unless best_alt
    @battle.pbRegisterMove(user_battler.index, best_alt[0], false)
    @battle.pbRegisterTarget(user_battler.index, best_alt[2]) if best_alt[2] && best_alt[2] >= 0
    PBDebug.log_ai("=> Sucker Punch mind game: swapped to #{best_alt[4].name}")
  end

  #override choose move - remove turn count limit
  def pbChooseMove(choices)
    user_battler = @user.battler
    max_score = choices.map { |c| c[1] }.max || 0
    if choices.length == 0
      @battle.pbAutoChooseMove(user_battler.index)
      PBDebug.log_ai("#{@user.name} will auto-use a move or Struggle")
      return
    end

    threshold = [max_score - 20, 120].min
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
    try_sucker_punch_mindgame(choices, user_battler)
    chosen_move = @battle.choices[user_battler.index][2]
    if chosen_move
      if @battle.choices[user_battler.index][3] >= 0
        PBDebug.log_ai("=> will use #{chosen_move.name} (target #{@battle.choices[user_battler.index][3]})")
      else
        PBDebug.log_ai("=> will use #{chosen_move.name}")
      end
    end
    # PBDebug.flush
  end

  #override pbChooseToSwitchOut — only called when all moves score < 80
  def pbChooseToSwitchOut(terrible_moves = true, threshold: REPLACEMENT_THRESHOLD_TERRIBLE_MOVES)
    return false if !@battle.canSwitch   # Battle rule
    return false if @user.wild?
    return false if !@battle.pbCanSwitchOut?(@user.index)
    # 1) Try replacement at threshold 80
    idxParty = choose_best_replacement_pokemon(@user.index, false, threshold: threshold)
    if idxParty < 0
      PBDebug.log_ai("   => no replacement at threshold #{threshold}, trying ShouldSwitch handlers")
      # 2) ShouldSwitch handlers gate a lower threshold (70)
      if @trainer.has_skill_flag?("ConsiderSwitching")
        reserves = get_non_active_party_pokemon(@user.index)
        if !reserves.empty?
          should_switch = Battle::AI::Handlers.should_switch?(@user, reserves, self, @battle)
          if should_switch && @trainer.medium_skill?
            should_switch = false if Battle::AI::Handlers.should_not_switch?(@user, reserves, self, @battle)
          end
          if should_switch
            idxParty = choose_best_replacement_pokemon(@user.index, false, threshold: threshold - 10)
          end
        end
      end
    end
    if idxParty < 0
      PBDebug.log_ai("   => no good replacement Pokémon, will not switch after all")
      return false
    end
    if @battle.pbRegisterSwitch(@user.index, idxParty)
      PBDebug.log_ai("=> will switch with #{@battle.pbParty(@user.index)[idxParty].name}")
      register_fresh_switch_score(@user.index, idxParty)
      return true
    end
    return false
  end

  # Record the replacement score so the AI
  # won't immediately switch it out on its first turn unless something better
  # comes along.
  def register_fresh_switch_score(idxBattler, idxParty)
    @_fresh_switch_scores ||= {}
    pkmn = @battle.pbParty(idxBattler)[idxParty]
    @_fresh_switch_scores[idxBattler] = {
      score:       @_last_replacement_score || 100,
      personal_id: pkmn.personalID,
      foe_ids:     current_foe_personal_ids(idxBattler)
    }
    PBDebug.log_ai("  [fresh_switch] stored score #{@_fresh_switch_scores[idxBattler][:score]} for #{pkmn.name}")
  end

  def current_foe_personal_ids(idxBattler)
    @battle.allOtherSideBattlers(idxBattler).map { |b| b.pokemon&.personalID }.compact.sort
  end

  def choose_best_replacement_pokemon(idxBattler, forced_switch = false, threshold: REPLACEMENT_THRESHOLD_TERRIBLE_MOVES)
    # Clear caches only on forced switches (faints/pivots) where a different
    # Pokémon now occupies the battler index, invalidating cached results.
    if forced_switch
      @_ai_dmg_cache = {}
      @_matchup_cache = {}
      invalidate_sim_cache
    end

    # Get all possible replacement Pokémon
    party = @battle.pbParty(idxBattler)
    reserves = []
    party.each_with_index do |_pkmn, i|
      next if !@battle.pbCanSwitchIn?(idxBattler, i)
      unless forced_switch   # Choosing an action for the round
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
    # Double KO: both sides fainted and are sending in fresh replacements,
    # meaning we don't know what the player chose — pick randomly.
    if forced_switch && @battle.battlers[idxBattler].fainted?
      # Check if our battler's underlying Pokémon still has HP (i.e. was
      # recalled alive, not truly KO'd). 
      truly_fainted = @battle.pbParty(idxBattler).none? { |pkmn|
        pkmn && pkmn == @battle.battlers[idxBattler].pokemon && pkmn.hp > 0
      }
      if truly_fainted
        foe_is_unknown = true
        @battle.allOtherSideBattlers(idxBattler).each do |b|
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
    end
    reserves = scored_replacement_candidates(idxBattler, forced_switch, party, reserves)
    @_last_replacement_score = reserves[0][1]
    # Fresh switch-in protection: if the current battler just switched in
    # (turnCount == 0) and hasn't acted yet, require the replacement to beat its
    # original replacement score — prevents flip-flopping.
    battler = @battle.battlers[idxBattler]
    fresh = (@_fresh_switch_scores || {})[idxBattler]
    if fresh && battler.turnCount == 0 && !battler.fainted? &&
        battler.pokemon&.personalID == fresh[:personal_id]
      current_foes = current_foe_personal_ids(idxBattler)
      if fresh[:foe_ids] && fresh[:foe_ids] != current_foes
        PBDebug.log_ai("=> fresh switch-in protection skipped for #{battler.name}: foe changed from #{fresh[:foe_ids].inspect} to #{current_foes.inspect}")
      elsif reserves[0][1] <= fresh[:score]
        PBDebug.log_ai("=> fresh switch-in #{battler.name} (entry score #{fresh[:score]}) >= best replacement #{party[reserves[0][0]].name} (#{reserves[0][1]}), not switching")
        return -1
      else
        PBDebug.log_ai("=> fresh switch-in #{battler.name} (entry score #{fresh[:score]}) beaten by #{party[reserves[0][0]].name} (#{reserves[0][1]})")
      end
    end
    if reserves[0][1] < threshold
      if forced_switch
        # Must switch (faint/pivot) — just pick the highest-scored reserve
        PBDebug.log_ai("=> forced switch: sacking #{party[reserves[0][0]].name} (best score #{reserves[0][1]})")
        return reserves[0][0]
      end
      PBDebug.log_ai("=> staying in: all reserves scored < #{threshold} (best: #{reserves[0][1]}), not switching")
      return -1
    end
    # Return the party index of the best rated replacement Pokémon
    return reserves[0][0]
  end

  def scored_replacement_candidates(idxBattler, forced_switch, party, reserves)
    battler = @battle.battlers[idxBattler]
    cache_key = [
      idxBattler,
      forced_switch,
      @battle.command_phase,
      battler.pokemon&.personalID,
      battler.pokemonIndex,
      reserves.map { |reserve| reserve[0] }
    ]
    @_replacement_score_cache ||= {}
    cached = @_replacement_score_cache[cache_key]
    return cached.map(&:dup) if cached

    scored = reserves.map do |reserve|
      pkmn = party[reserve[0]]
      replacement_1v1_results(idxBattler, pkmn)
      score = rate_replacement_pokemon(idxBattler, pkmn, reserve[1])
      PBDebug.log_ai("pokemon #{party[reserve[0]].name} has switch score #{score}")
      [reserve[0], score]
    end
    scored.sort! { |a, b| b[1] <=> a[1] }
    @_replacement_score_cache[cache_key] = scored.map(&:dup)
    return scored
  end

  #override
  def rate_replacement_pokemon(idxBattler, pkmn, score)
    # The actual calculations are deferred to handlers
    score = Battle::AI::Handlers.score_replacement(idxBattler, pkmn, score, @battle, self)
    return score.to_i
  end
end

module Battle::AI::Handlers
  ScoreReplacement = HandlerHash.new

  def self.score_replacement(idxBattler, pkmn, score, battle, user_ai)
    ScoreReplacement.each do |id, score_proc|
      new_score = score_proc.call(idxBattler, pkmn, score, battle, user_ai)
      score = new_score if new_score
    end
    return score
  end
end
