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

#-------------------------------------------------------------------------------
# Lagging Tail / Full Incense: override faster_than? to account for
# PriorityBracketChange items that force the holder to move last.
#-------------------------------------------------------------------------------
LAGGING_TAIL_ITEMS = [:LAGGINGTAIL, :FULLINCENSE]

class Battle::AI::AIBattler
  alias _tower_orig_faster_than? faster_than?
  def faster_than?(other)
    return false if other.nil?
    self_lagging  = LAGGING_TAIL_ITEMS.include?(battler.item_id) && battler.itemActive?
    other_lagging = LAGGING_TAIL_ITEMS.include?(other.battler.item_id) && other.battler.itemActive?
    # If only one side has a lagging item, that side is always slower
    return false if self_lagging && !other_lagging
    return true  if other_lagging && !self_lagging
    # Both or neither — fall through to normal speed comparison
    _tower_orig_faster_than?(other)
  end
end

class Battle::AI
  MOVE_FAIL_SCORE = -999
  REPLACEMENT_THRESHOLD_NORMAL = 105
  REPLACEMENT_THRESHOLD_TERRIBLE_MOVES = 80

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

  def safe_types(obj)
    return [] if !obj
    return obj.pbTypes(true) if obj.respond_to?(:pbTypes)
    return obj.types if obj.respond_to?(:types)
    return []
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
    # 3. Score moves FIRST
    choices = pbGetMoveScores
    # 4. Try items only if best move score is mediocre
    max_move_score = choices.map { |c| c[1] }.max || 0
    if max_move_score < MOVE_BASE_SCORE
      ret = false
      PBDebug.logonerr { ret = pbChooseToUseItem }
      if ret
        PBDebug.log("")
        return
      end
    end
    # 5. Choose move as normal
    pbChooseMove(choices)
    PBDebug.log("")
    pbRegisterEnemySpecialAction2(idxBattler)
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
      else
        # Doomed attacker: foe will OHKO, we can't KO back — consider switching
        has_sub = @user.effects[PBEffects::Substitute] > 0
        unless has_sub
          summary = matchup_summary
          if summary[:foe_can_ohko] && !summary[:user_can_ko_any] && max_score < MOVE_BASE_SCORE + 50
            PBDebug.log_ai("#{@user.name} is doomed (foe OHKOs, can't KO back). Considering switch.")
            if pbChooseToSwitchOut(false, skip_should_switch: true)
              @battle.pbUnregisterMegaEvolution(@user.index)
              return
            end
            PBDebug.log_ai("#{@user.name} will attack despite being doomed")
          end
        end
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
    # Double KO: both sides fainted and are sending in fresh replacements,
    # meaning we don't know what the player chose — pick randomly.
    # Does NOT apply to pivot switches where the foe is visible on field.
    if forced_switch && @battle.battlers[idxBattler].fainted?
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
    # Rate each possible replacement Pokémon
    reserves.each_with_index do |reserve, i|
      reserves[i][1] = rate_replacement_pokemon(idxBattler, party[reserve[0]], reserve[1], terrible_moves)
      PBDebug.log_ai("pokemon #{party[reserve[0]].name} has switch score #{reserves[i][1]}")
    end
    reserves.sort! { |a, b| b[1] <=> a[1] }   # Sort from highest to lowest rated
    threshold = terrible_moves ? REPLACEMENT_THRESHOLD_TERRIBLE_MOVES : REPLACEMENT_THRESHOLD_NORMAL
    # Raise threshold if switching dooms current Pokemon to hazard death
    unless forced_switch
      threshold = [threshold + hazard_death_threshold_bonus(idxBattler, reserves), 110].min
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

  #override
  def rate_replacement_pokemon(idxBattler, pkmn, score, terrible_moves = false)
    # The actual calculations are deferred to handlers
    score = Battle::AI::Handlers.score_replacement(idxBattler, pkmn, score, terrible_moves, @battle, self)
    return score.to_i
  end

  # Returns a threshold bonus (0 or 20) if switching out would doom the current
  # Pokemon to hazard death on re-entry, with no way to mitigate it.
  def hazard_death_threshold_bonus(idxBattler, reserves)
    current_pkmn = @battle.pbParty(idxBattler)[@battle.battlers[idxBattler].pokemonIndex]
    own_side = idxBattler & 1
    hazard_dmg = calculate_entry_hazard_damage(current_pkmn, own_side)
    return 0 if hazard_dmg < current_pkmn.hp
    # Current mon dies to hazards on re-entry — check for outs
    party = @battle.pbParty(idxBattler)
    hazard_clear_codes = [
      "RemoveUserBindingAndEntryHazards",            # Rapid Spin
      "RemoveUserBindingAndEntryHazardsPoisonTarget", # Mortal Spin
      "LowerTargetEvasion1RemoveSideEffects"          # Defog
    ]
    reserves.each do |r|
      rpkmn = party[r[0]]
      rpkmn.moves.each do |m|
        return 0 if hazard_clear_codes.include?(m.function_code)
      end
    end
    # No hazard clearer — check for HP healing items
    items = @battle.pbGetOwnerItems(idxBattler)
    items.each do |itm|
      return 0 if @battle.pbItemHealsHP?(itm)
    end
    PBDebug.log_ai("Hazard death: current mon dies to hazards, no clearer, no healing items — raising threshold by 20")
    return 20
  end

end

module Battle::AI::Handlers
  ScoreReplacement = HandlerHash.new

  def self.score_replacement(idxBattler, pkmn, score, terrible_moves, battle, user_ai)
    ScoreReplacement.each do |id, score_proc|
      new_score = score_proc.call(idxBattler, pkmn, score, terrible_moves, battle, user_ai)
      score = new_score if new_score
    end
    return score
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
end
