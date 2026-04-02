#===============================================================================
# Battle Simulation: Deep-copy once, restore in-place for subsequent sims.
#
# The first create_battle_copy call per decision cycle deep-copies the real
# Battle and builds a mapping (real object_id → sim object).  Subsequent
# calls restore the cached sim from the real battle by walking the mapping
# and overwriting ivars/contents — no new object allocation.
#===============================================================================

class Battle::AI
  # Symbol used with throw/catch to abort simulation on forced switch attempts.
  SIM_SWITCH_TRIGGERED = :sim_switch_triggered

  # Minimum interval between scene ticks during AI computation (~7 FPS).
  TICK_INTERVAL = 0.05

  #=============================================================================
  # SilentScene: No-op scene for simulation.
  #=============================================================================
  class SilentScene
    def method_missing(_method, *_args, &_block); nil; end
    def respond_to_missing?(_method, _include_private = false); true; end
  end

  #---------------------------------------------------------------------------
  # Tick the battle scene to keep sprites and animations alive during AI.
  # Throttled so Graphics.update overhead doesn't dominate computation.
  #---------------------------------------------------------------------------
  def tick_scene
    now = System.uptime
    return if @_last_tick && (now - @_last_tick) < TICK_INTERVAL
    @_last_tick = now
    scene = @battle.scene
    return unless scene.is_a?(Battle::Scene)
    scene.pbGraphicsUpdate
    scene.pbFrameUpdate
  end

  #---------------------------------------------------------------------------
  # Show/hide a "..." thinking indicator in the message window.
  #---------------------------------------------------------------------------
  def show_thinking_indicator
    scene = @battle.scene
    return unless scene.is_a?(Battle::Scene)
    scene.pbShowWindow(Battle::Scene::MESSAGE_BOX)
    msgw = scene.sprites["messageWindow"]
    return unless msgw
    msgw.letterbyletter = false
    msgw.setText("...")
    msgw.letterbyletter = true
    @_thinking_shown = true
    tick_scene
  end

  def hide_thinking_indicator
    return unless @_thinking_shown
    scene = @battle.scene
    return unless scene.is_a?(Battle::Scene)
    scene.sprites["messageBox"]&.visible = false
    msgw = scene.sprites["messageWindow"]
    if msgw
      msgw.text = ""
      msgw.visible = false
    end
    @_thinking_shown = false
  end

  #---------------------------------------------------------------------------
  # Return a battle copy for simulation.  First call per decision cycle does
  # a full deep copy and caches the result + object mapping.  Subsequent
  # calls restore the cached copy in-place from the real battle.
  #---------------------------------------------------------------------------
  def create_battle_copy
    tick_scene
    cache_key = [@battle.turnCount, @user&.index]
    if @_sim_template && @_sim_cache_key == cache_key
      restore_sim_from_real
      tick_scene
      return @_sim_template
    end
    # Full deep copy + build real→sim mapping
    @_real_to_sim = {}
    saved_scene = @battle.instance_variable_get(:@scene)
    @battle.instance_variable_set(:@scene, nil)
    begin
      @_sim_template = deep_copy(@battle, @_real_to_sim)
    ensure
      @battle.instance_variable_set(:@scene, saved_scene)
    end
    @_sim_template.instance_variable_set(:@scene, SilentScene.new)
    @_sim_template.instance_variable_set(:@is_simulation, true)
    # Abort simulation on any switch attempt, but preserve whether it was a
    # faint replacement or a live battler leaving mid-turn.
    sim = @_sim_template
    def sim.pbSwitchInBetween(idxBattler, checkLaxOnly = false, canCancel = false)
      battler = @battlers[idxBattler]
      reason = if @endOfRound || (battler && battler.fainted?)
                 :replacement
               else
                 :live_switch
               end
      throw Battle::AI::SIM_SWITCH_TRIGGERED, { reason: reason, battler_index: idxBattler }
    end
    @_sim_cache_key = cache_key
    tick_scene
    @_sim_template
  end

  # Invalidate the sim template cache (called on forced switches, etc.)
  def invalidate_sim_cache
    @_sim_template = nil
    @_real_to_sim = nil
    @_sim_cache_key = nil
  end

  # Scope AI-only caches to a single decision so they don't accumulate across
  # the whole battle while still being shared by nested simulations.
  def with_decision_cache
    @_decision_cache_depth ||= 0
    reset_decision_caches if @_decision_cache_depth == 0
    @_decision_cache_depth += 1
    yield
  ensure
    @_decision_cache_depth = [(@_decision_cache_depth || 1) - 1, 0].max
    reset_decision_caches if @_decision_cache_depth == 0
  end

  def reset_decision_caches
    @_ai_dmg_cache = nil
    @_matchup_cache = nil
    @_known_foe_moves_cache = nil
    @_replacement_score_cache = nil
    invalidate_sim_cache
  end

  private

  #---------------------------------------------------------------------------
  # Deep copy that builds a mapping from real object_id → sim object.
  # The mapping is used both for cycle detection during copy and for
  # in-place restoration on subsequent simulation calls.
  #---------------------------------------------------------------------------
  def deep_copy(obj, mapping)
    case obj
    when nil, true, false, Numeric, Symbol, Method, Proc
      return obj
    end
    return mapping[obj.object_id] if mapping.key?(obj.object_id)

    case obj
    when String
      copy = obj.dup
      mapping[obj.object_id] = copy
      return copy
    when Array
      copy = []
      mapping[obj.object_id] = copy
      obj.each { |e| copy << deep_copy(e, mapping) }
    when Hash
      copy = {}
      mapping[obj.object_id] = copy
      entries = obj.to_a
      entries.each { |k, v| copy[deep_copy(k, mapping)] = deep_copy(v, mapping) }
    else
      copy = obj.class.allocate
      mapping[obj.object_id] = copy
      obj.instance_variables.each do |ivar|
        tick_scene
        copy.instance_variable_set(ivar, deep_copy(obj.instance_variable_get(ivar), mapping))
      end
    end
    tick_scene
    copy
  end

  #---------------------------------------------------------------------------
  # Restore the cached sim template from the real battle's current state.
  # Walks the real battle's object graph via the mapping and overwrites
  # each sim object's state without allocating new objects.
  #---------------------------------------------------------------------------
  def restore_sim_from_real
    saved_scene = @battle.instance_variable_get(:@scene)
    @battle.instance_variable_set(:@scene, nil)
    begin
      restore_object(@battle, @_real_to_sim, {})
    ensure
      @battle.instance_variable_set(:@scene, saved_scene)
    end
    @_sim_template.instance_variable_set(:@scene, SilentScene.new)
    @_sim_template.instance_variable_set(:@is_simulation, true)
  end

  #---------------------------------------------------------------------------
  # Recursively restore a sim object's state from its real counterpart.
  # - Strings: replace contents
  # - Arrays/Hashes: clear and rebuild with mapped references
  # - Objects: overwrite ivars with mapped values, remove stale ivars
  #---------------------------------------------------------------------------
  def restore_object(real_obj, mapping, visited)
    case real_obj
    when nil, true, false, Numeric, Symbol, Method, Proc
      return
    end
    return if visited.key?(real_obj.object_id)
    sim_obj = mapping[real_obj.object_id]
    return unless sim_obj
    visited[real_obj.object_id] = true

    case real_obj
    when String
      sim_obj.replace(real_obj)
    when Array
      sim_obj.clear
      real_obj.each do |elem|
        sim_obj << (mapping[elem.object_id] || elem)
        restore_object(elem, mapping, visited)
      end
    when Hash
      sim_obj.clear
      real_obj.each do |k, v|
        sim_obj[mapping[k.object_id] || k] = mapping[v.object_id] || v
        restore_object(k, mapping, visited)
        restore_object(v, mapping, visited)
      end
    else
      real_obj.instance_variables.each do |ivar|
        tick_scene
        real_val = real_obj.instance_variable_get(ivar)
        sim_obj.instance_variable_set(ivar, mapping[real_val.object_id] || real_val)
        restore_object(real_val, mapping, visited)
      end
      # Remove ivars that were added during previous simulation
      extra = sim_obj.instance_variables - real_obj.instance_variables
      extra.each { |ivar| sim_obj.remove_instance_variable(ivar) } unless extra.empty?
    end
  end
end

#===============================================================================
# Primal weather constants
#===============================================================================
PRIMAL_WEATHERS = [:HarshSun, :HeavyRain, :StrongWinds].freeze

#===============================================================================
# Simulation support: expose is_simulation flag on Battle.
#===============================================================================
class Battle
  attr_accessor :is_simulation
end

#===============================================================================
# Suppress low-chance crits during AI simulations.
# Only allow crit checks when the crit rate is >= 50% (ratio <= 2, i.e. stage 2+),
# while preserving normal randomness for those allowed crit stages.
# This prevents lucky RNG from skewing AI damage predictions.
#===============================================================================
class Battle::Move
  alias _orig_pbIsCritical pbIsCritical?
  def pbIsCritical?(user, target)
    if @battle.is_simulation
      return false if target.pokemon.immunities.include?(:CRITICALHIT)
      return false if target.pbOwnSide.effects[PBEffects::LuckyChant] > 0
      c = 0
      if c >= 0 && user.abilityActive?
        c = Battle::AbilityEffects.triggerCriticalCalcFromUser(user.ability, user, target, c)
      end
      if c >= 0 && target.abilityActive? && !@battle.moldBreaker
        c = Battle::AbilityEffects.triggerCriticalCalcFromTarget(target.ability, user, target, c)
      end
      if c >= 0 && user.itemActive?
        c = Battle::ItemEffects.triggerCriticalCalcFromUser(user.item, user, target, c)
      end
      if c >= 0 && target.itemActive?
        c = Battle::ItemEffects.triggerCriticalCalcFromTarget(target.item, user, target, c)
      end
      return false if c < 0
      # Move-specific overrides (always/never crit)
      case pbCritialOverride(user, target)
      when 1  then return true
      when -1 then return false
      end
      # Guaranteed-crit effects
      return true if c > 50   # Merciless
      return true if user.effects[PBEffects::LaserFocus] > 0
      # Compute final crit stage (DBK uses crit_stage_bonuses)
      c += crit_stage_bonuses(user)
      ratios = CRITICAL_HIT_RATIOS
      c = ratios.length - 1 if c >= ratios.length
      return false if ratios[c] > 2
      return true if ratios[c] == 1
      r = @battle.pbRandom(ratios[c])
      return true if r == 0
    end
    _orig_pbIsCritical(user, target)
  end
end

#===============================================================================
# Suppress misses for moves with >= 70% accuracy during AI simulations.
#===============================================================================
class Battle::Move
  alias _orig_pbBaseAccuracy pbBaseAccuracy
  def pbBaseAccuracy(user, target)
    acc = _orig_pbBaseAccuracy(user, target)
    if @battle && @battle.is_simulation && acc >= 70
      # 0 = always hits for some reason
      return 0
    end
    return acc
  end
end

#===============================================================================
# Suppress low-chance additional effects during AI simulations.
# Secondary effects below 50% are treated as never occurring, while effects with
# 50%+ odds keep their normal randomness.
#===============================================================================
class Battle::Move
  alias _orig_pbAdditionalEffectChance pbAdditionalEffectChance
  def pbAdditionalEffectChance(user, target, effectChance = 0)
    chance = _orig_pbAdditionalEffectChance(user, target, effectChance)
    if @battle && @battle.is_simulation && chance > 0 && chance < 50
      return 0
    end
    return chance
  end
end

#===============================================================================
# Suppress random damage variance during AI simulations.
# Uses a fixed midpoint (92/100) instead of random 85-100 for consistent
# damage estimates in pbCalcDamage calls.
#===============================================================================
class Battle::Move
  alias _orig_pbCalcDamageMults_Random pbCalcDamageMults_Random
  def pbCalcDamageMults_Random(user, target, numTargets, type, baseDmg, multipliers)
    if @battle && @battle.is_simulation
      # Critical hits (reuse existing sim crit logic via pbIsCritical?)
      if target.damageState.critical
        if Settings::NEW_CRITICAL_HIT_RATE_MECHANICS
          multipliers[:final_damage_multiplier] *= 1.5
        else
          multipliers[:final_damage_multiplier] *= 2
        end
      end
      # Fixed variance instead of random
      if !self.is_a?(Battle::Move::Confusion)
        multipliers[:final_damage_multiplier] *= 92 / 100.0
      end
      return
    end
    _orig_pbCalcDamageMults_Random(user, target, numTargets, type, baseDmg, multipliers)
  end
end

#===============================================================================
# Allow Sucker Punch (FailsIfTargetActed) to succeed during pure damage checks
# where the opponent's action is forced to [:None] in the simulation.
#===============================================================================
class Battle::Move::FailsIfTargetActed < Battle::Move
  if !method_defined?(:_orig_pbFailsAgainstTarget?)
    alias _orig_pbFailsAgainstTarget? pbFailsAgainstTarget?
    def pbFailsAgainstTarget?(user, target, show_message)
      if @battle && @battle.is_simulation && @battle.choices[target.index][0] == :None
        return false
      end
      return _orig_pbFailsAgainstTarget?(user, target, show_message)
    end
  end
end
