#===============================================================================
# SimBattler: Full battle simulation wrapper for AI damage calculations.
# Replaces AIBattler with complete Battler duck-typing for actual pbCalcDamage.
#===============================================================================

class Battle::AI
  #=============================================================================
  # SilentScene: No-op scene that swallows all UI calls during simulation.
  #=============================================================================
  class SilentScene
    def method_missing(_method, *_args, &_block)
      nil
    end

    def respond_to_missing?(_method, _include_private = false)
      true
    end

    # Explicitly define common methods for performance
    def pbDisplay(_msg); end
    def pbDisplayBrief(_msg); end
    def pbDisplayPaused(_msg); end
    def pbShowAnimation(*); end
    def pbCommonAnimation(*); end
    def pbHPChanged(*); end
    def pbHitAndHPLossAnimation(*); end
    def pbDamageAnimation(*); end
    def pbFaintBattler(*); end
    def pbRecall(*); end
    def pbRefresh; end
    def pbRefreshOne(*); end
    def pbShowAbilitySplash(*); end
    def pbHideAbilitySplash(*); end
    def pbReplaceAbilitySplash(*); end
    def pbShowOpposingAbilitySplash(*); end
    def pbSEPlay(*); end
    def pbBGMPlay(*); end
    def pbMEPlay(*); end
    def pbWait(*); end
    def pbUpdate(*); end
    def pbShowPartyLineup(*); end
  end

  #=============================================================================
  # SimBattler: Wraps real Battler or raw Pokemon with mutable sim state.
  # Owns its own damageState and intercepts all write methods.
  #=============================================================================
  class SimBattler
    attr_reader :damageState
    attr_accessor :sim_hp, :sim_totalhp
    attr_accessor :sim_attack, :sim_defense, :sim_spatk, :sim_spdef, :sim_speed
    attr_accessor :sim_stages
    attr_accessor :sim_status, :sim_statusCount
    attr_accessor :sim_ability_id, :sim_item_id
    attr_accessor :sim_types, :sim_level
    attr_accessor :sim_effects
    attr_accessor :sim_moves
    attr_accessor :sim_form, :sim_species
    attr_accessor :sim_battle   # SimBattle reference for field state
    attr_reader   :source_pokemon # raw Pokemon for reserves (nil for active battlers)
    attr_reader   :ai, :index, :side, :battler

    LAGGING_TAIL_ITEMS = [:LAGGINGTAIL, :FULLINCENSE].freeze

    #---------------------------------------------------------------------------
    # Constructors
    #---------------------------------------------------------------------------
    def initialize(ai, battler)
      @ai = ai
      @battler = battler
      @index = battler.index
      @side = ai.battle.opposes?(@index) ? 1 : 0
      @source_pokemon = nil
      @damageState = Battle::DamageState.new
      @sim_battle = nil
      populate_from_battler
    end

    # Create SimBattler from raw Pokemon (for reserves)
    def self.from_pokemon(ai, index, pkmn)
      obj = allocate
      obj.instance_variable_set(:@ai, ai)
      obj.instance_variable_set(:@index, index)
      obj.instance_variable_set(:@side, ai.battle.opposes?(index) ? 1 : 0)
      obj.instance_variable_set(:@battler, nil)
      obj.instance_variable_set(:@source_pokemon, pkmn)
      obj.instance_variable_set(:@damageState, Battle::DamageState.new)
      obj.instance_variable_set(:@sim_battle, nil)
      obj.populate_from_pokemon(pkmn)
      obj
    end

    #---------------------------------------------------------------------------
    # State population
    #---------------------------------------------------------------------------
    def populate_from_battler
      b = @battler
      @sim_hp          = b.hp
      @sim_totalhp     = b.totalhp
      @sim_attack      = b.instance_variable_get(:@attack)
      @sim_defense     = b.instance_variable_get(:@defense)
      @sim_spatk       = b.instance_variable_get(:@spatk)
      @sim_spdef       = b.instance_variable_get(:@spdef)
      @sim_speed       = b.instance_variable_get(:@speed)
      @sim_stages      = b.stages.dup
      @sim_status      = b.status
      @sim_statusCount = b.statusCount
      @sim_ability_id  = b.ability_id
      @sim_item_id     = b.item_id
      @sim_types       = b.pbTypes(true).dup
      @sim_level       = b.level
      @sim_effects     = b.effects.dup
      @sim_moves       = b.moves
      @sim_form        = b.form
      @sim_species     = b.species
      @damageState.reset
      # Z-Power / Deluxe Kit state
      @selectedMoveIsZMove = false
      @lastMoveUsedIsZMove = false
      @baseMoves           = []
      @powerMoveIndex      = -1
    end

    def populate_from_pokemon(pkmn)
      pkmn.calc_stats
      @sim_hp          = pkmn.hp
      @sim_totalhp     = pkmn.totalhp
      @sim_attack      = pkmn.attack
      @sim_defense     = pkmn.defense
      @sim_spatk       = pkmn.spatk
      @sim_spdef       = pkmn.spdef
      @sim_speed       = pkmn.speed
      @sim_stages      = {}
      GameData::Stat.each_battle { |s| @sim_stages[s.id] = 0 }
      @sim_status      = pkmn.status
      @sim_statusCount = pkmn.statusCount
      @sim_ability_id  = pkmn.ability_id
      @sim_item_id     = pkmn.item_id
      @sim_types       = pkmn.types.dup
      @sim_level       = pkmn.level
      @sim_effects     = _default_effects
      @sim_moves       = pkmn.moves.map { |m| Battle::Move.from_pokemon_move(@ai.battle, m) }
      @sim_form        = pkmn.form
      @sim_species     = pkmn.species
      @damageState.reset
      # Z-Power / Deluxe Kit state
      @selectedMoveIsZMove = false
      @lastMoveUsedIsZMove = false
      @baseMoves           = []
      @powerMoveIndex      = -1
    end

    def reset_sim_state!
      if @battler
        populate_from_battler
      elsif @source_pokemon
        populate_from_pokemon(@source_pokemon)
      end
    end

    def refresh_battler
      populate_from_battler if @battler
    end

    #---------------------------------------------------------------------------
    # Default effects hash for reserves
    #---------------------------------------------------------------------------
    def _default_effects
      eff = []
      eff[PBEffects::AquaRing]       = false
      eff[PBEffects::Charge]         = 0
      eff[PBEffects::Confusion]      = 0
      eff[PBEffects::Curse]          = false
      eff[PBEffects::Disable]        = 0
      eff[PBEffects::DisableMove]    = nil
      eff[PBEffects::Encore]         = 0
      eff[PBEffects::EncoreMove]     = nil
      eff[PBEffects::FlashFire]      = false
      eff[PBEffects::FocusEnergy]    = 0
      eff[PBEffects::Foresight]      = false
      eff[PBEffects::GastroAcid]     = false
      eff[PBEffects::GemConsumed]    = nil
      eff[PBEffects::HealBlock]      = 0
      eff[PBEffects::HyperBeam]      = 0
      eff[PBEffects::Ingrain]        = false
      eff[PBEffects::LaserFocus]     = 0
      eff[PBEffects::LeechSeed]      = -1
      eff[PBEffects::MagnetRise]     = 0
      eff[PBEffects::Minimize]       = false
      eff[PBEffects::MiracleEye]     = false
      eff[PBEffects::Nightmare]      = false
      eff[PBEffects::PerishSong]     = 0
      eff[PBEffects::PerishSongUser] = -1
      eff[PBEffects::Protect]        = false
      eff[PBEffects::ProtectRate]    = 1
      eff[PBEffects::SmackDown]      = false
      eff[PBEffects::Substitute]     = 0
      eff[PBEffects::TarShot]        = false
      eff[PBEffects::Taunt]          = 0
      eff[PBEffects::Telekinesis]    = 0
      eff[PBEffects::Torment]        = false
      eff[PBEffects::Toxic]          = 0
      eff[PBEffects::Transform]      = false
      eff[PBEffects::Trapping]       = 0
      eff[PBEffects::TrappingUser]   = -1
      eff[PBEffects::Truant]         = false
      eff[PBEffects::TwoTurnAttack]  = nil
      eff[PBEffects::Unburden]       = false
      eff[PBEffects::Yawn]           = 0
      eff[PBEffects::Attract]        = -1
      eff[PBEffects::BurnUp]         = false
      eff[PBEffects::ChoiceBand]     = nil
      eff[PBEffects::ExtraType]      = nil
      eff[PBEffects::Flinch]         = false
      eff[PBEffects::Illusion]       = nil
      eff[PBEffects::MeanLook]       = -1
      eff[PBEffects::NoRetreat]      = false
      eff[PBEffects::Outrage]        = 0
      eff[PBEffects::ParentalBond]   = 0
      eff[PBEffects::Pinch]          = false
      eff[PBEffects::Prankster]      = false
      eff[PBEffects::Rollout]        = 0
      eff[PBEffects::SlowStart]      = 0
      eff[PBEffects::Stockpile]      = 0
      eff[PBEffects::WeightChange]   = 0
      eff[PBEffects::GlaiveRush]     = 0 if defined?(PBEffects::GlaiveRush)
      eff[PBEffects::Embargo]        = 0
      eff
    end

    #===========================================================================
    # Accessor overrides — read from sim state
    #===========================================================================
    def hp;          @sim_hp;          end
    def totalhp;     @sim_totalhp;     end
    def level;       @sim_level;       end
    def status;      @sim_status;      end
    def statusCount; @sim_statusCount; end
    def effects;     @sim_effects;     end
    def stages;      @sim_stages;      end
    def moves;       @sim_moves;       end
    def types;       @sim_types;       end
    def form;        @sim_form;        end
    def species;     @sim_species;     end
    def attack;      @sim_attack;      end
    def spatk;       @sim_spatk;       end
    def speed;       @sim_speed;       end

    def defense
      return @sim_spdef if field_effect(PBEffects::WonderRoom) > 0
      @sim_defense
    end

    def spdef
      return @sim_defense if field_effect(PBEffects::WonderRoom) > 0
      @sim_spdef
    end

    # Helper to read field effects from sim_battle or real battle
    def field_effect(effect)
      if @sim_battle
        @sim_battle.field.effects[effect]
      else
        @ai.battle.field.effects[effect]
      end
    end

    # Helper to check moldBreaker from sim_battle or real battle
    def mold_breaker?
      @sim_battle ? @sim_battle.moldBreaker : @ai.battle.moldBreaker
    end

    def fainted?;    @sim_hp <= 0;     end
    def ability_id;  @sim_ability_id;  end
    def ability;     GameData::Ability.try_get(@sim_ability_id); end
    def item_id;     @sim_item_id;     end
    def item;        GameData::Item.try_get(@sim_item_id);       end

    def pokemon
      return @battler.pokemon if @battler
      @source_pokemon
    end

    #---------------------------------------------------------------------------
    # Write interception methods (for simulation)
    #---------------------------------------------------------------------------
    def hp=(val);          @sim_hp = val;          end
    def status=(val);      @sim_status = val;      end
    def statusCount=(val); @sim_statusCount = val; end
    def ability_id=(val);  @sim_ability_id = val;  end
    def item_id=(val);     @sim_item_id = val;     end
    def form=(val);        @sim_form = val;        end

    # HP reduction (called by move effects)
    def pbReduceHP(amt, anim = true, registerDamage = true, anyAnim = true)
      amt = amt.round.clamp(1, @sim_hp)
      @sim_hp -= amt
      @damageState.hpLost = amt
      @damageState.totalHPLost += amt
      amt
    end

    # HP recovery
    def pbRecoverHP(amt, anim = true, anyAnim = true)
      amt = amt.round.clamp(0, @sim_totalhp - @sim_hp)
      @sim_hp += amt
      amt
    end

    def pbRecoverHPFromDrain(amt, target, msg = nil)
      pbRecoverHP(amt, false, false)
    end

    # Stat stage changes
    def pbRaiseStatStage(stat, increment, user = nil, showAnim = true, ignoreContrary = false)
      return false if @sim_stages[stat] >= 6
      increment = [increment, 6 - @sim_stages[stat]].min
      @sim_stages[stat] += increment if increment > 0
      increment > 0
    end

    def pbRaiseStatStageByCause(stat, increment, user, cause, showAnim = true, ignoreContrary = false)
      pbRaiseStatStage(stat, increment, user, showAnim, ignoreContrary)
    end

    def pbLowerStatStage(stat, decrement, user = nil, showAnim = true, ignoreContrary = false, ignoreMirrorArmor = false)
      return false if @sim_stages[stat] <= -6
      decrement = [decrement, @sim_stages[stat] + 6].min
      @sim_stages[stat] -= decrement if decrement > 0
      decrement > 0
    end

    def pbLowerStatStageByCause(stat, decrement, user, cause, showAnim = true, ignoreContrary = false, ignoreMirrorArmor = false)
      pbLowerStatStage(stat, decrement, user, showAnim, ignoreContrary, ignoreMirrorArmor)
    end

    def pbLowerAttackStatStageIntimidate(user)
      pbLowerStatStage(:ATTACK, 1, user)
    end

    # Status infliction
    def pbInflictStatus(status, count = 0, msg = nil, user = nil)
      @sim_status = status
      @sim_statusCount = count
      true
    end

    def pbCureStatus(showMessages = true)
      @sim_status = :NONE
      @sim_statusCount = 0
    end

    def pbCureConfusion
      @sim_effects[PBEffects::Confusion] = 0
    end

    def pbCureAttract
      @sim_effects[PBEffects::Attract] = -1
    end

    def pbFaint(showMessage = true)
      @sim_hp = 0
    end

    #---------------------------------------------------------------------------
    # Type methods
    #---------------------------------------------------------------------------
    def has_type?(type)
      return false unless type
      pbTypes(true).include?(GameData::Type.get(type).id)
    end
    alias pbHasType? has_type?

    def pbTypes(withExtraType = false)
      ret = @sim_types.dup
      if withExtraType && @sim_effects[PBEffects::ExtraType]
        extra = @sim_effects[PBEffects::ExtraType]
        ret.push(extra) unless ret.include?(extra)
      end
      ret
    end

    #---------------------------------------------------------------------------
    # Ability/item active checks
    #---------------------------------------------------------------------------
    def ability_active?(check_ability = nil)
      return false if fainted?
      return false if @sim_effects[PBEffects::GastroAcid]
      true
    end
    alias abilityActive? ability_active?

    def has_active_ability?(ability, ignore_fainted = false)
      return false if !ignore_fainted && fainted?
      return false if @sim_effects[PBEffects::GastroAcid]
      ability = [ability] unless ability.is_a?(Array)
      ability.include?(@sim_ability_id)
    end
    alias hasActiveAbility? has_active_ability?

    def has_mold_breaker?
      return false unless ability_active?
      [:MOLDBREAKER, :TERAVOLT, :TURBOBLAZE, :MYCELIUMMIGHT].include?(@sim_ability_id)
    end
    alias hasMoldBreaker? has_mold_breaker?

    def item_active?
      return false if fainted?
      return false if @sim_item_id.nil?
      return false if @sim_effects[PBEffects::Embargo] && @sim_effects[PBEffects::Embargo] > 0
      return false if field_effect(PBEffects::MagicRoom) > 0
      return false if has_active_ability?(:KLUTZ)
      true
    end
    alias itemActive? item_active?

    def has_active_item?(item_check)
      return false unless item_active?
      item_check = [item_check] unless item_check.is_a?(Array)
      item_check.include?(@sim_item_id)
    end
    alias hasActiveItem? has_active_item?

    #---------------------------------------------------------------------------
    # Stat helpers
    #---------------------------------------------------------------------------
    def statStageAtMax?(stat)
      @sim_stages[stat] >= Battle::Battler::STAT_STAGE_MAXIMUM
    end

    def statStageAtMin?(stat)
      @sim_stages[stat] <= -Battle::Battler::STAT_STAGE_MAXIMUM
    end

    def pbCanRaiseStatStage?(stat, user = nil, move = nil, showFailMsg = false, ignoreContrary = false)
      return false if fainted?
      return false if statStageAtMax?(stat)
      true
    end

    def pbCanLowerStatStage?(stat, user = nil, move = nil, showFailMsg = false, ignoreContrary = false, ignoreMirrorArmor = false)
      return false if fainted?
      return false if statStageAtMin?(stat)
      true
    end

    def base_stat(stat)
      case stat
      when :ATTACK          then attack
      when :DEFENSE         then defense
      when :SPECIAL_ATTACK  then spatk
      when :SPECIAL_DEFENSE then spdef
      when :SPEED           then speed
      else 0
      end
    end

    def rough_stat(stat)
      return pbSpeed if stat == :SPEED
      stage_mul = Battle::Battler::STAT_STAGE_MULTIPLIERS
      stage_div = Battle::Battler::STAT_STAGE_DIVISORS
      if [:ACCURACY, :EVASION].include?(stat)
        stage_mul = Battle::Battler::ACC_EVA_STAGE_MULTIPLIERS
        stage_div = Battle::Battler::ACC_EVA_STAGE_DIVISORS
      end
      stage = @sim_stages[stat] + Battle::Battler::STAT_STAGE_MAXIMUM
      value = base_stat(stat)
      (value.to_f * stage_mul[stage] / stage_div[stage]).floor
    end

    def plainStats
      {
        ATTACK:          attack,
        DEFENSE:         defense,
        SPECIAL_ATTACK:  spatk,
        SPECIAL_DEFENSE: spdef,
        SPEED:           speed
      }
    end

    #---------------------------------------------------------------------------
    # Speed calculation
    #---------------------------------------------------------------------------
    def pbSpeed
      return 1 if fainted?
      stage = @sim_stages[:SPEED] + Battle::Battler::STAT_STAGE_MAXIMUM
      spd = @sim_speed * Battle::Battler::STAT_STAGE_MULTIPLIERS[stage] /
                         Battle::Battler::STAT_STAGE_DIVISORS[stage]
      speedMult = 1.0
      speedMult = Battle::AbilityEffects.triggerSpeedCalc(ability, self, speedMult) if ability_active?
      speedMult = Battle::ItemEffects.triggerSpeedCalc(item, self, speedMult) if item_active?
      speedMult *= 2 if pbOwnSide.effects[PBEffects::Tailwind] > 0
      speedMult /= 2 if pbOwnSide.effects[PBEffects::Swamp] > 0
      if @sim_status == :PARALYSIS && !has_active_ability?(:QUICKFEET)
        speedMult /= (Settings::MECHANICS_GENERATION >= 7) ? 2 : 4
      end
      if @ai.battle.internalBattle && pbOwnedByPlayer? &&
         @ai.battle.pbPlayer.badge_count >= Settings::NUM_BADGES_BOOST_SPEED
        speedMult *= 1.1
      end
      [(spd * speedMult).round, 1].max
    end

    def faster_than?(other)
      return false if other.nil?
      self_lagging  = LAGGING_TAIL_ITEMS.include?(@sim_item_id) && item_active?
      other_lagging = LAGGING_TAIL_ITEMS.include?(other.item_id) && other.item_active?
      return false if self_lagging && !other_lagging
      return true  if other_lagging && !self_lagging
      pbSpeed > other.pbSpeed
    end

    #---------------------------------------------------------------------------
    # Weight
    #---------------------------------------------------------------------------
    def pbWeight
      ret = pokemon ? pokemon.weight : 500
      ret += @sim_effects[PBEffects::WeightChange]
      ret = 1 if ret < 1
      if ability_active? && !mold_breaker?
        ret = Battle::AbilityEffects.triggerWeightCalc(ability, self, ret)
      end
      ret = Battle::ItemEffects.triggerWeightCalc(item, self, ret) if item_active?
      [ret, 1].max
    end

    #---------------------------------------------------------------------------
    # Airborne/terrain checks
    #---------------------------------------------------------------------------
    def airborne?
      return false if has_active_item?(:IRONBALL)
      return false if @sim_effects[PBEffects::Ingrain]
      return false if @sim_effects[PBEffects::SmackDown]
      return false if field_effect(PBEffects::Gravity) > 0
      return true  if has_type?(:FLYING)
      return true  if has_active_ability?(:LEVITATE) && !mold_breaker?
      return true  if has_active_item?(:AIRBALLOON)
      return true  if @sim_effects[PBEffects::MagnetRise] > 0
      return true  if @sim_effects[PBEffects::Telekinesis] > 0
      false
    end

    def affectedByTerrain?
      return false if airborne?
      return false if semiInvulnerable?
      true
    end

    SEMI_INVULNERABLE_FUNCTIONS = %w[
      TwoTurnAttackInvulnerableInSky
      TwoTurnAttackInvulnerableUnderground
      TwoTurnAttackInvulnerableUnderwater
      TwoTurnAttackInvulnerableInSkyParalyzeTarget
      TwoTurnAttackInvulnerableRemoveProtections
      TwoTurnAttackInvulnerableInSkyTargetCannotAct
    ].freeze

    def semiInvulnerable?
      tta = @sim_effects[PBEffects::TwoTurnAttack]
      return false unless tta
      ttaFunction = GameData::Move.get(tta).function_code
      SEMI_INVULNERABLE_FUNCTIONS.include?(ttaFunction)
    end

    def inTwoTurnAttack?(*funcs)
      tta = @sim_effects[PBEffects::TwoTurnAttack]
      return false unless tta
      ttaFunction = GameData::Move.get(tta).function_code
      funcs.any? { |f| f == ttaFunction }
    end

    #---------------------------------------------------------------------------
    # Weather (reads from sim_battle or real field)
    #---------------------------------------------------------------------------
    def effectiveWeather
      weather = @sim_battle ? @sim_battle.field.weather : @ai.battle.pbWeather
      if [:Sun, :Rain, :HarshSun, :HeavyRain].include?(weather) && has_active_item?(:UTILITYUMBRELLA)
        weather = :None
      end
      weather
    end

    #---------------------------------------------------------------------------
    # Side/position accessors
    #---------------------------------------------------------------------------
    def idxOwnSide;     @index & 1;                    end
    def idxOpposingSide; (@index & 1) ^ 1;             end
    def pbOwnSide;      @sim_battle ? @sim_battle.sides[idxOwnSide] : @ai.battle.sides[idxOwnSide]; end
    def pbOpposingSide; @sim_battle ? @sim_battle.sides[idxOpposingSide] : @ai.battle.sides[idxOpposingSide]; end

    def allAllies
      battle = @sim_battle || @ai.battle
      battle.allSameSideBattlers(@index).select { |b| b.index != @index }
    end

    def allOpposing
      battle = @sim_battle || @ai.battle
      battle.allOtherSideBattlers(@index)
    end

    def pbOwnedByPlayer?
      return @battler.pbOwnedByPlayer? if @battler
      !@ai.battle.opposes?(@index)
    end

    def near?(other)
      other_idx = other.is_a?(Integer) ? other : other.index
      @ai.battle.nearBattlers?(@index, other_idx)
    end

    def opposes?(other = nil)
      return @side == 1 if other.nil?
      other_side = other.is_a?(Integer) ? (@ai.battle.opposes?(other) ? 1 : 0) : other.side
      other_side != @side
    end

    #---------------------------------------------------------------------------
    # Species/form checks
    #---------------------------------------------------------------------------
    def isSpecies?(check_species)
      @sim_species == check_species
    end

    def name
      pkmn = pokemon
      n = pkmn ? pkmn.name : "???"
      sprintf("%s (%d)", n, @index)
    end

    def wild?
      return @battler.wild? if @battler
      # Reserve battler - check if side 1 and wild battle
      @side == 1 && @ai.battle.wildBattle?
    end

    def can_switch_lax?
      return false if wild?
      return false if @ai.battle.pbSideSize(@index) > 1  # Double/Triple battle restrictions
      true
    end

    #---------------------------------------------------------------------------
    # Mega/Tera/Primal/Dynamax
    #---------------------------------------------------------------------------
    def mega?;           pokemon&.mega?;                        end
    def hasMega?
      return false if @sim_effects[PBEffects::Transform]
      pokemon&.hasMegaForm?
    end
    def primal?;         pokemon&.primal?;                      end
    def tera?;           @battler ? @battler.tera? : false;     end
    def tera_type;       @battler&.tera_type || pokemon&.tera_type; end
    def dynamax?;        @battler ? @battler.dynamax? : false;  end
    def shadowPokemon?;  false;                                 end
    def inHyperMode?;    false;                                 end

    #---------------------------------------------------------------------------
    # Offensive stats (for Tera Blast category check)
    #---------------------------------------------------------------------------
    def getOffensiveStats
      max_stage = Battle::Battler::STAT_STAGE_MAXIMUM
      stageMul  = Battle::Battler::STAT_STAGE_MULTIPLIERS
      stageDiv  = Battle::Battler::STAT_STAGE_DIVISORS
      atk       = attack
      atkStage  = @sim_stages[:ATTACK] + max_stage
      realAtk   = (atk.to_f * stageMul[atkStage] / stageDiv[atkStage]).floor
      spAtk     = spatk
      spAtkStage = @sim_stages[:SPECIAL_ATTACK] + max_stage
      realSpAtk = (spAtk.to_f * stageMul[spAtkStage] / stageDiv[spAtkStage]).floor
      [realAtk, realSpAtk]
    end

    #---------------------------------------------------------------------------
    # Status helpers
    #---------------------------------------------------------------------------
    def asleep?;    @sim_status == :SLEEP;     end
    def frozen?;    @sim_status == :FROZEN;    end
    def poisoned?;  @sim_status == :POISON;    end
    def burned?;    @sim_status == :BURN;      end
    def paralyzed?; @sim_status == :PARALYSIS; end

    def pbHasAnyStatus?
      if Battle::AbilityEffects.triggerStatusCheckNonIgnorable(self.ability, self, nil)
        return true
      end
      @sim_status != :NONE
    end

    def pbCanSleep?(user, showMessages, move = nil, ignorestatus = false)
      return false if fainted?
      return false unless ignorestatus || @sim_status == :NONE
      return false if has_type?(:GRASS) && has_active_ability?(:FLOWERVEIL)
      true
    end

    def pbCanPoison?(user, showMessages, move = nil)
      return false if fainted?
      return false unless @sim_status == :NONE
      return false if has_type?(:POISON) || has_type?(:STEEL)
      true
    end

    def pbCanBurn?(user, showMessages, move = nil)
      return false if fainted?
      return false unless @sim_status == :NONE
      return false if has_type?(:FIRE)
      true
    end

    def pbCanParalyze?(user, showMessages, move = nil)
      return false if fainted?
      return false unless @sim_status == :NONE
      return false if has_type?(:ELECTRIC) && Settings::MECHANICS_GENERATION >= 6
      true
    end

    def pbCanFreeze?(user, showMessages, move = nil)
      return false if fainted?
      return false unless @sim_status == :NONE
      return false if has_type?(:ICE)
      true
    end

    def pbCanConfuse?(user = nil, showMessages = true, move = nil, selfInflicted = false)
      return false if fainted?
      return false if @sim_effects[PBEffects::Confusion] > 0
      true
    end

    def pbCanAttract?(user, showMessages = true)
      return false if fainted?
      return false if @sim_effects[PBEffects::Attract] >= 0
      true
    end

    #---------------------------------------------------------------------------
    # Misc delegations
    #---------------------------------------------------------------------------
    def gender;          pokemon ? pokemon.gender : 0;          end
    def nature;          pokemon ? pokemon.nature : nil;        end
    def happiness;       pokemon ? pokemon.happiness : 0;       end
    def affection_level; pokemon ? pokemon.affection_level : 2; end
    def turnCount;       @battler ? @battler.turnCount : 0;     end
    def pokemonIndex;    @battler ? @battler.pokemonIndex : 0;  end
    def battle;          @sim_battle || @ai.battle;             end

    def pbCanChooseMove?(move, commandPhase = true, showMessages = false)
      return @battler.pbCanChooseMove?(move, commandPhase, showMessages) if @battler
      move && (move.pp > 0 || move.total_pp == 0)
    end

    def hasLoweredStatStages?
      GameData::Stat.each_battle { |s| return true if @sim_stages[s.id] < 0 }
      false
    end

    def pbPreTeraTypes
      return @battler.pbPreTeraTypes if @battler&.respond_to?(:pbPreTeraTypes)
      @sim_types
    end

    def typeTeraBoosted?(type, override = false)
      return @battler.typeTeraBoosted?(type, override) if @battler&.respond_to?(:typeTeraBoosted?)
      false
    end

    def affectedByPowder?
      return false if has_type?(:GRASS)
      return false if has_active_ability?(:OVERCOAT) && !mold_breaker?
      return false if has_active_item?(:SAFETYGOGGLES)
      true
    end

    def isCommander?
      @battler&.respond_to?(:isCommander?) ? @battler.isCommander? : false
    end

    def takesIndirectDamage?(showMsg = false)
      return false if fainted?
      return false if has_active_ability?(:MAGICGUARD)
      true
    end

    def canHeal?
      return false if fainted?
      return false if @sim_hp >= @sim_totalhp
      true
    end

    def trappedInBattle?
      @battler ? @battler.trappedInBattle? : false
    end

    def unstoppableAbility?(ability_id = nil)
      @battler&.respond_to?(:unstoppableAbility?) ? @battler.unstoppableAbility?(ability_id) : false
    end

    def isRaidBoss?
      @battler&.respond_to?(:isRaidBoss?) ? @battler.isRaidBoss? : false
    end

    def damageThreshold
      @battler&.respond_to?(:damageThreshold) ? @battler.damageThreshold : nil
    end
    def damageThreshold=(val); end
    def stopBoostedHPScaling;  false; end
    def stopBoostedHPScaling=(val); end

    def can_attack?
      return false if fainted?
      return false if @sim_effects[PBEffects::HyperBeam] > 0
      return false if @sim_effects[PBEffects::Truant]
      true
    end

    # AIBattler compatibility: effects accessor
    def effects
      @sim_effects
    end

    # AIBattler compatibility: check_for_move
    # Yields each move and returns true if any block returns true
    def check_for_move
      moves.each { |m| return true if yield(m) }
      false
    end

    # AIBattler compatibility: has_move_with_function?
    def has_move_with_function?(*funcs)
      moves.each do |m|
        next unless m
        return true if funcs.include?(m.function_code)
      end
      false
    end

    # AIBattler compatibility: opponent_side_has_ability?
    def opponent_side_has_ability?(abilities)
      abilities = [abilities] unless abilities.is_a?(Array)
      @ai.each_foe_battler(@side) do |b, _|
        abilities.each { |a| return true if b.has_active_ability?(a) }
      end
      false
    end

    # AIBattler compatibility: opponent_side_has_move_flags?
    def opponent_side_has_move_flags?(*flags)
      @ai.each_foe_battler(@side) do |b, _|
        b.moves.each do |m|
          next unless m
          flags.each { |f| return true if m.flags.include?(f) }
        end
      end
      false
    end

    #---------------------------------------------------------------------------
    # End-of-round damage estimation
    #---------------------------------------------------------------------------
    def rough_end_of_round_damage
      damage = 0
      # Poison
      if @sim_status == :POISON
        damage += @sim_effects[PBEffects::Toxic] > 0 ? @sim_totalhp / 8 : @sim_totalhp / 8
      end
      # Burn
      damage += @sim_totalhp / 16 if @sim_status == :BURN
      # Leech Seed
      damage += @sim_totalhp / 8 if @sim_effects[PBEffects::LeechSeed] >= 0
      # Curse
      damage += @sim_totalhp / 4 if @sim_effects[PBEffects::Curse]
      # Nightmare
      damage += @sim_totalhp / 4 if @sim_effects[PBEffects::Nightmare] && asleep?
      # Trapping moves
      damage += @sim_totalhp / 8 if @sim_effects[PBEffects::Trapping] > 0
      # Healing
      damage -= @sim_totalhp / 16 if @sim_effects[PBEffects::AquaRing]
      damage -= @sim_totalhp / 16 if @sim_effects[PBEffects::Ingrain]
      # Leftovers/Black Sludge
      if has_active_item?(:LEFTOVERS)
        damage -= @sim_totalhp / 16
      elsif has_active_item?(:BLACKSLUDGE)
        damage -= @sim_totalhp / 16 if has_type?(:POISON)
        damage += @sim_totalhp / 8 unless has_type?(:POISON)
      end
      damage
    end

    #---------------------------------------------------------------------------
    # Z-Move / Deluxe Kit compatibility
    #---------------------------------------------------------------------------
    attr_accessor :selectedMoveIsZMove, :lastMoveUsedIsZMove, :baseMoves, :powerMoveIndex

    def display_base_moves
      return if @baseMoves.empty?
      @sim_moves.length.times do |i|
        next unless @baseMoves[i]
        @sim_moves[i] = @baseMoves[i].is_a?(Battle::Move) ? @baseMoves[i] : Battle::Move.from_pokemon_move(@ai.battle, @baseMoves[i])
      end
      @baseMoves.clear
    end

    def display_zmoves
      return unless hasCompatibleZMove?
      item_data = GameData::Item.get(@sim_item_id)
      pkmn = @sim_effects[PBEffects::TransformPokemon] || pokemon
      @sim_moves.length.times do |i|
        @baseMoves.push(@sim_moves[i])
        new_id = @sim_moves[i].get_compatible_zmove(item_data, pkmn)
        next unless new_id
        @sim_moves[i]          = @sim_moves[i].make_zmove(new_id, @ai.battle)
        @sim_moves[i].pp       = [@baseMoves[i].pp, 1].min
        @sim_moves[i].total_pp = 1
      end
    end

    def hasCompatibleZMove?(baseMove = nil)
      return false unless @sim_item_id
      item = GameData::Item.get(@sim_item_id)
      return false unless item.is_zcrystal?
      return false if @sim_effects[PBEffects::Transform] && item.is_ultra_item?
      moves_to_check = baseMove.nil? ? @sim_moves : [baseMove]
      if item.has_zmove_combo?
        return false unless GameData::Move.get(item.zmove).zMove?
        return false unless moves_to_check.any? { |m| m.id == item.zmove_base_move }
        pkmn = @sim_effects[PBEffects::TransformPokemon] || pokemon
        check_species = item.has_flag?("UsableByAllForms") ? pkmn.species : pkmn.species_data.id
        return item.zmove_species.include?(check_species)
      else
        return moves_to_check.any? { |m| m.type == item.zmove_type }
      end
    end

    def hasZMove?
      return false if shadowPokemon?
      return false unless [nil, :ultra].include?(getActiveState)
      hasCompatibleZMove?
    end

    def hasZCrystal?
      return false unless @sim_item_id
      GameData::Item.get(@sim_item_id).is_zcrystal?
    end

    def getActiveState
      return :mega    if mega?
      return :primal  if primal?
      return :dynamax if dynamax?
      return :tera    if tera?
      nil
    end

    #---------------------------------------------------------------------------
    # AIBattler compatibility: effectiveness_of_type_against_battler
    # Base implementation that can be extended by plugin overrides
    #---------------------------------------------------------------------------
    def effectiveness_of_type_against_battler(type, user = nil, move = nil)
      ret = Effectiveness::NORMAL_EFFECTIVE_MULTIPLIER
      return ret unless type
      # Handle Stellar type from Terastallization
      if type == :STELLAR
        ret = Effectiveness::SUPER_EFFECTIVE_MULTIPLIER if tera?
        return ret
      end
      # Calculate normal type effectiveness
      pbTypes(true).each do |defend_type|
        ret *= Effectiveness.calculate(type, defend_type)
      end
      # Check for ability modifiers
      if ability_active?
        ret = Battle::AbilityEffects.triggerModifyTypeEffectiveness(
          ability_id, user, @battler || self, move, @ai.battle, ret
        ) if defined?(Battle::AbilityEffects.triggerModifyTypeEffectiveness)
      end
      ret
    end
  end
end
