#===============================================================================
# Battle Simulation: Deep-copy based sim reuse.
#
# We deep-copy the real Battle (minus its scene) once at the start of the
# AI turn and cache it.  Each create_battle_copy call deep-copies from
# that cached clean copy, giving each simulation a fresh independent state.
#===============================================================================

class Battle::AI
  # Symbol used with throw/catch to abort simulation on forced switch attempts.
  SIM_SWITCH_TRIGGERED = :sim_switch_triggered

  # Minimum interval between scene ticks during AI computation (~7 FPS).
  TICK_INTERVAL = 0.15

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
  # Return a fresh deep copy of the real battle for simulation.
  #---------------------------------------------------------------------------
  def create_battle_copy
    saved_scene = @battle.instance_variable_get(:@scene)
    @battle.instance_variable_set(:@scene, nil)
    begin
      sim = deep_copy(@battle)
    ensure
      @battle.instance_variable_set(:@scene, saved_scene)
    end
    sim.instance_variable_set(:@scene, SilentScene.new)
    sim.instance_variable_set(:@is_simulation, true)
    # Abort simulation on any forced switch attempt (U-turn, Eject Pack, etc.)
    def sim.pbSwitchInBetween(idxBattler, checkLaxOnly = false, canCancel = false)
      throw Battle::AI::SIM_SWITCH_TRIGGERED
    end
    sim
  end

  private

  #---------------------------------------------------------------------------
  # Custom recursive deep copy.
  # Uses an identity map (`seen`) to preserve shared references and avoid
  # infinite recursion on circular object graphs.
  #---------------------------------------------------------------------------
  def deep_copy(obj, seen = {})
    # Immutable types — return as-is
    case obj
    when nil, true, false, Numeric, Symbol, Method, Proc
      return obj
    when String
      return obj.dup
    end

    # Already copied this exact object — return the same copy
    return seen[obj.object_id] if seen.key?(obj.object_id)

    case obj
    when Array
      copy = []
      seen[obj.object_id] = copy
      obj.each { |e| copy << deep_copy(e, seen) }
    when Hash
      copy = {}
      seen[obj.object_id] = copy
      obj.each { |k, v| copy[deep_copy(k, seen)] = deep_copy(v, seen) }
    else
      # Generic object: allocate a bare instance, then deep-copy each ivar
      copy = obj.class.allocate
      seen[obj.object_id] = copy
      obj.instance_variables.each do |ivar|
        copy.instance_variable_set(ivar, deep_copy(obj.instance_variable_get(ivar), seen))
      end
    end
    copy
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
# Only allow crits when the crit rate is >= 50% (ratio <= 2, i.e. stage 2+).
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
      # Only crit if chance >= 50% (ratio <= 2)
      return ratios[c] <= 2
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
      return 0
    end
    return acc
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
