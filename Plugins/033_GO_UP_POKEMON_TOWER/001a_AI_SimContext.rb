#===============================================================================
# SimBattle: Full battle simulation wrapper for AI calculations.
# Wraps a real Battle with mutable simulated state that can be reset.
#===============================================================================

class Battle::AI
  #=============================================================================
  # SimField: Simulated field state (weather, terrain, effects)
  #=============================================================================
  class SimField
    attr_accessor :weather, :weatherDuration
    attr_accessor :terrain, :terrainDuration
    attr_accessor :effects

    def initialize(real_field)
      @real_field = real_field
      reset!
    end

    def reset!
      @weather = @real_field.weather
      @weatherDuration = @real_field.weatherDuration
      @terrain = @real_field.terrain
      @terrainDuration = @real_field.terrainDuration
      @effects = @real_field.effects.dup
    end
  end

  #=============================================================================
  # SimSide: Simulated side effects (Reflect, Spikes, etc.)
  #=============================================================================
  class SimSide
    attr_accessor :effects

    def initialize(real_side)
      @real_side = real_side
      reset!
    end

    def reset!
      @effects = @real_side.effects.dup
    end
  end

  #=============================================================================
  # SimPosition: Simulated position effects
  #=============================================================================
  class SimPosition
    attr_accessor :effects

    def initialize(real_position)
      @real_position = real_position
      reset!
    end

    def reset!
      @effects = @real_position ? @real_position.effects.dup : {}
    end
  end

  #=============================================================================
  # SimBattle: Wraps a real Battle with simulated mutable state.
  # Self-contained - no delegation to real battle.
  #=============================================================================
  class SimBattle
    attr_accessor :field, :sides, :positions, :battlers, :choices
    attr_accessor :turnCount, :lastMoveUsed, :lastMoveUser, :moldBreaker
    attr_accessor :deterministic
    attr_reader   :real_battle

    def initialize(ai)
      @ai = ai
      @real_battle = ai.battle
      @deterministic = true
      @field = SimField.new(@real_battle.field)
      @sides = [SimSide.new(@real_battle.sides[0]), SimSide.new(@real_battle.sides[1])]
      @positions = @real_battle.positions.map { |p| SimPosition.new(p) }
      @battlers = []  # Populated with SimBattlers by caller
      @choices = []
      reset!
    end

    def reset!
      @field.reset!
      @sides.each(&:reset!)
      @positions.each(&:reset!)
      @turnCount = @real_battle.turnCount
      @lastMoveUsed = @real_battle.lastMoveUsed
      @lastMoveUser = @real_battle.lastMoveUser
      @moldBreaker = @real_battle.moldBreaker
      @choices = @real_battle.choices.map { |c| c.dup rescue c }
    end

    #---------------------------------------------------------------------------
    # Deterministic random for simulation
    #---------------------------------------------------------------------------
    def pbRandom(x)
      return x / 2 if @deterministic
      rand(x)
    end

    def damage_roll
      @deterministic ? 92 : (85 + rand(16))
    end

    #---------------------------------------------------------------------------
    # Methods using simulated battler state
    #---------------------------------------------------------------------------
    def allBattlers
      @battlers.select { |b| b && !b.fainted? }
    end

    def allSameSideBattlers(idx)
      @battlers.select { |b| b && !b.fainted? && !opposes?(b.index, idx) }
    end

    def allOtherSideBattlers(idx)
      @battlers.select { |b| b && !b.fainted? && opposes?(b.index, idx) }
    end

    def pbAllFainted?(idx = 0)
      @battlers.each do |b|
        next if !b || opposes?(b.index, idx)
        return false if !b.fainted?
      end
      true
    end

    def opposes?(idx1, idx2 = 0)
      idx1.even? != idx2.even?
    end

    #---------------------------------------------------------------------------
    # Silent scene for simulation
    #---------------------------------------------------------------------------
    def scene
      SilentScene.new
    end

    def showAnims
      false
    end

    #---------------------------------------------------------------------------
    # Display methods (no-op in simulation)
    #---------------------------------------------------------------------------
    def pbDisplay(_msg); end
    def pbDisplayBrief(_msg); end
    def pbDisplayPaused(_msg); end
    def pbShowAbilitySplash(*); end
    def pbHideAbilitySplash(*); end
  end
end

#===============================================================================
# Primal weather constants (shared with SimBattler/simulation code)
#===============================================================================
PRIMAL_WEATHERS = [:HarshSun, :HeavyRain, :StrongWinds].freeze
