#===============================================================================
# New PBEffects used by certain cheers.
#===============================================================================
module PBEffects
  CheerOffense1 = 827
  CheerOffense2 = 828
  CheerOffense3 = 829
  CheerDefense1 = 830
  CheerDefense2 = 831
  CheerDefense3 = 832
end

class Battle::ActiveSide
  alias cheer_initialize initialize
  def initialize
    cheer_initialize
    @effects[PBEffects::CheerOffense1] = 0
    @effects[PBEffects::CheerOffense2] = 0
	@effects[PBEffects::CheerOffense3] = 0
	@effects[PBEffects::CheerDefense1] = 0
	@effects[PBEffects::CheerDefense2] = 0
	@effects[PBEffects::CheerDefense3] = 0
  end
end

module Battle::DebugVariables
  SIDE_EFFECTS[PBEffects::CheerOffense1] = { name: "Offense cheer Lv.1 duration", default: 0 }
  SIDE_EFFECTS[PBEffects::CheerOffense2] = { name: "Offense cheer Lv.2 duration", default: 0 }
  SIDE_EFFECTS[PBEffects::CheerOffense3] = { name: "Offense cheer Lv.3 duration", default: 0 }
  SIDE_EFFECTS[PBEffects::CheerDefense1] = { name: "Defense cheer Lv.1 duration", default: 0 }
  SIDE_EFFECTS[PBEffects::CheerDefense2] = { name: "Defense cheer Lv.2 duration", default: 0 }
  SIDE_EFFECTS[PBEffects::CheerDefense3] = { name: "Defense cheer Lv.3 duration", default: 0 }
end

#===============================================================================
# Battle class additions for the Cheer command.
#===============================================================================
class Battle
  attr_accessor :cheerMode, :cheerLevel
  
  #-----------------------------------------------------------------------------
  # Aliased to initialize new cheer properties.
  #-----------------------------------------------------------------------------
  alias cheer_initialize initialize
  def initialize(*args)
    cheer_initialize(*args)
	@cheerMode  = nil
	@cheerLevel = [
      [0] * (@player ? @player.length : 1),
      [0] * (@opponent ? @opponent.length : 1)
    ]
  end

  #-----------------------------------------------------------------------------
  # Aliased to convert the Call command into Cheer when cheering is possible.
  #-----------------------------------------------------------------------------
  alias cheer_pbCallMenu pbCallMenu
  def pbCallMenu(idxBattler)
    if canCheer?(idxBattler)
	  if hasCheer?(idxBattler, true)
        idxCheer = @scene.pbChooseCheer(@cheerMode)
        return pbRegisterCheer(idxBattler, idxCheer)
	  end
    else
      return cheer_pbCallMenu(idxBattler)
    end
  end
  
  #-----------------------------------------------------------------------------
  # Aliased for Lv.3 Defense Cheer effects.
  #-----------------------------------------------------------------------------
  alias cheer_pbAttackPhase pbAttackPhase
  def pbAttackPhase
    @sides.each_with_index do |side, i|
	  if side.effects[PBEffects::CheerDefense3] > 0
	    allSameSideBattlers(i).each do |b|
		  b.effects[PBEffects::Endure] = true
		end
	  end
	end
    cheer_pbAttackPhase
  end
  
  #-----------------------------------------------------------------------------
  # Aliased to increase Cheer level at the end of each round.
  #-----------------------------------------------------------------------------
alias cheer_pbEndOfRoundPhase pbEndOfRoundPhase
def pbEndOfRoundPhase
  ret = cheer_pbEndOfRoundPhase
  return ret if @cheerMode.nil? || @decision > 0
  [@player, @opponent].each_with_index do |trainers, side|
    next if !trainers
    @cheerLevel[side].length.times do |i|
      next if pbAbleTeamCounts(side)[i] == 0
      oldLvl = @cheerLevel[side][i]
      next if oldLvl >= 3
      @cheerLevel[side][i] += 1
      newLvl = @cheerLevel[side][i]
      name = (side == 0 && i == 0) ? trainers[i].name : trainers[i].full_name
      if newLvl > 0
        if newLvl < 3
          pbDisplay(_INTL("{1}의 응원 레벨이 올라가고 있다!", name))
        else
          pbDisplay(_INTL("{1}의 응원 레벨이 최대로 올랐다!", name))
        end
        pbDeluxeTriggers(side, nil, "CheerLevel", newLvl)
      end
      PBDebug.log("[Cheer level] #{trainers[i].full_name}'s Cheer level changed (#{oldLvl} => #{newLvl})")
    end
  end
  return ret
end
  
  #-----------------------------------------------------------------------------
  # Aliased to count down Offense and Defense cheer effects.
  #-----------------------------------------------------------------------------
# Battle class 내부에 위치
alias cheer_pbEOREndSideEffects pbEOREndSideEffects
  alias cheer_pbEOREndSideEffects pbEOREndSideEffects
  def pbEOREndSideEffects(side, priority)
    cheer_pbEOREndSideEffects(side, priority)
    pbEORCountDownSideEffect(side, PBEffects::CheerOffense1,
                             _INTL("{1}의 전력을 다하려는 의지가 희미해졌다!", @battlers[side].pbTeam))
	pbEORCountDownSideEffect(side, PBEffects::CheerOffense2,
                             _INTL("{1}의 더 강하게 공격하려는 의지가 희미해졌다!", @battlers[side].pbTeam))						 
	pbEORCountDownSideEffect(side, PBEffects::CheerOffense3,
                             _INTL("{1}의 배리어를 뚫고 나가려는 의지가 희미해졌다!", @battlers[side].pbTeam))
    pbEORCountDownSideEffect(side, PBEffects::CheerDefense1,
                             _INTL("{1}의 끈기 있게 버티려는 의지가 희미해졌다!", @battlers[side].pbTeam))
	pbEORCountDownSideEffect(side, PBEffects::CheerDefense2,
                             _INTL("{1}의 급소와 기술 효과를 무시하려는 의지가 희미해졌다!", @battlers[side].pbTeam))
	pbEORCountDownSideEffect(side, PBEffects::CheerDefense3,
                             _INTL("{1}의 공격을 견뎌내려는 의지가 희미해졌다!", @battlers[side].pbTeam))
  end	
  
  #-----------------------------------------------------------------------------
  # Aliased to utilize all selected Cheer commands.
  #-----------------------------------------------------------------------------
  alias cheer_pbAttackPhaseSpecialActions3 pbAttackPhaseSpecialActions3
  def pbAttackPhaseSpecialActions3
    cheer_pbAttackPhaseSpecialActions3
    pbPriority.each do |b|
      next unless @choices[b.index][0] == :Cheer && !b.fainted?
      b.lastMoveFailed = false
      pbCheer(b.index)
    end
  end
  
  #-----------------------------------------------------------------------------
  # Utilities for determining whether the Cheer command is usable.
  #-----------------------------------------------------------------------------
def canCheer?(idxBattler = 0)
  return false if @cheerMode.nil?
  return false if opposes?(idxBattler) && wildBattle?
  return true
end
  
def hasCheer?(idxBattler = 0, showMessages = false)
  if !canCheer?(idxBattler)
    pbDisplay(_INTL("응원은 이 배틀에서 사용할 수 없습니다.")) if showMessages
    return false
  end
  if allOwnedByTrainer(idxBattler).any? { |b| @choices[b.index][0] == :Cheer }
    pbDisplay(_INTL("이번 턴에 이미 응원을 사용하도록 선택했습니다.")) if showMessages
    return false
  end
  if pbOwnedByPlayer?(idxBattler) && @scene.sprites["cheerWindow"].cheers.empty?
    pbDisplay(_INTL("이 배틀에서 사용할 응원이 없습니다.")) if showMessages
    return false
  end
  return true
end
  
def pbCheerAlreadyInUse?(idxBattler, idxCheer)
  eachSameSideBattler(idxBattler) do |b|
    choices = @choices[b.index]
    return true if choices[0] == :Cheer && choices[1] == idxCheer
  end
  return false
end
  
#-----------------------------------------------------------------------------
# Registers the selected Cheer command.
#-----------------------------------------------------------------------------
def pbRegisterCheer(idxBattler, idxCheer)
  return false if idxCheer < 0
  @choices[idxBattler][0] = :Cheer
  @choices[idxBattler][1] = idxCheer
  @choices[idxBattler][2] = nil
  return true
end
  
#-----------------------------------------------------------------------------
# Utility for actually implementing the effects of a cheer.
#-----------------------------------------------------------------------------
def pbCheer(idxBattler)
  return if @choices[idxBattler][0] != :Cheer
  recipients = false
  battler = @battlers[idxBattler]
  side = battler.idxOwnSide
  owner = pbGetOwnerIndexFromBattlerIndex(idxBattler)
  trainerName = pbGetOwnerName(idxBattler)
  user = (owner == 0) ? "당신" : trainerName
  choice = @choices[idxBattler][1]
  cheer = @scene.sprites["cheerWindow"].cheers[choice]
  PBDebug.log("[Use cheer] #{battler.pbThis} (#{idxBattler}) used #{cheer.name}")
  pbDeluxeTriggers(idxBattler, nil, "BeforeCheer", cheer.id, battler.species)
  pbDisplay(_INTL("\\j[{1},이,가] {2}에게 응원합니다!\n{3}", user, battler.pbTeam(true), cheer.cheer_text))
  pbAnimation(:ENCORE, battler, battler)
  if Battle::Cheer.trigger(cheer.id, side, owner, battler, self)
    oldLvl = @cheerLevel[side][owner]
    @cheerLevel[side][owner] = -1
    trainers = (side == 0) ? @player : @opponent
    PBDebug.log("[Cheer level] #{trainers[owner].full_name}'s Cheer level changed (#{oldLvl} => 0)")
    pbDeluxeTriggers(idxBattler, nil, "AfterCheer", cheer.id, battler.species)
  else
    pbDisplay(_INTL("하지만, 응원의 목소리가 주변에 약하게 울려 퍼졌습니다..."))
    pbDeluxeTriggers(idxBattler, nil, "FailedCheer", cheer.id, battler.species)
  end
end
end

class SafariBattle
  def canCheer?(i = 0); return false; end
end

#===============================================================================
# Battle::Move class additions for cheer effects.
#===============================================================================
class Battle::Move
  attr_accessor :ignoreGuard
  
  #-----------------------------------------------------------------------------
  # Aliased for Lv.1 Offense and Defense Cheer effects.
  #-----------------------------------------------------------------------------
  # Offense : Increases damage dealt by 50%.
  # Defense : Reduces damage taken by 50%.
  #-----------------------------------------------------------------------------
  alias cheer_pbCalcDamageMults_Other pbCalcDamageMults_Other
  def pbCalcDamageMults_Other(user, target, numTargets, type, baseDmg, multipliers)
    cheer_pbCalcDamageMults_Other(user, target, numTargets, type, baseDmg, multipliers)
	return if self.is_a?(Battle::Move::Confusion)
	if user.pbOwnSide.effects[PBEffects::CheerOffense1] != 0
      multipliers[:power_multiplier] *= 1.5
    end
	if target.pbOwnSide.effects[PBEffects::CheerDefense1] != 0
      multipliers[:power_multiplier] /= 2
    end
  end
  
  #-----------------------------------------------------------------------------
  # Aliased for Lv.2 Offense and Defense Cheer effects.
  #-----------------------------------------------------------------------------
  # Offense : Guarantees added effects and critical hits triggering.
  # Defense : Negates added effects and critical hits from triggering.
  #-----------------------------------------------------------------------------
  alias cheer_pbAdditionalEffectChance pbAdditionalEffectChance
  def pbAdditionalEffectChance(user, target, effectChance = 0)
    return 0 if target && target.pbOwnSide.effects[PBEffects::CheerDefense2] != 0
	return 100 if user && user.pbOwnSide.effects[PBEffects::CheerOffense2] != 0
    return cheer_pbAdditionalEffectChance(user, target, effectChance)
  end
  
  alias cheer_pbIsCritical? pbIsCritical?
  def pbIsCritical?(user, target)
    return false if target.pbOwnSide.effects[PBEffects::CheerDefense2] != 0
	return true if user.pbOwnSide.effects[PBEffects::CheerOffense2] != 0
	return cheer_pbIsCritical?(user, target)
  end
  
  #-----------------------------------------------------------------------------
  # Aliased for Lv.3 Offense Cheer effects.
  #-----------------------------------------------------------------------------
  # Damaging moves ignore the effects of Protect-like moves, the effects of barriers 
  # such as Reflect/Light Screen/Aurora Veil, and will also hit through Substitute.
  #-----------------------------------------------------------------------------
  alias cheer_pbChangeUsageCounters pbChangeUsageCounters
  def pbChangeUsageCounters(user, specialUsage)
	cheer_pbChangeUsageCounters(user, specialUsage)
	@ignoreGuard = (damagingMove? && user.pbOwnSide.effects[PBEffects::CheerOffense3] != 0)
  end
  
  alias cheer_canProtectAgainst? canProtectAgainst?
  def canProtectAgainst?
    return false if @ignoreGuard
    return cheer_canProtectAgainst?
  end
  
  alias cheer_ignoresReflect? ignoresReflect?
  def ignoresReflect?
    return true if @ignoreGuard
    return cheer_ignoresReflect?
  end
  
  alias cheer_ignoresSubstitute? ignoresSubstitute?
  def ignoresSubstitute?(user)
    return true if @ignoreGuard
    return cheer_ignoresSubstitute?(user)
  end
end

#===============================================================================
# AI damage calcs for cheer effects.
#===============================================================================
class Battle::AI::AIMove
  alias cheer_calc_other_mults calc_other_mults
  def calc_other_mults(user, target, base_dmg, calc_type, is_critical, multipliers)
    cheer_calc_other_mults(user, target, base_dmg, calc_type, is_critical, multipliers)
	return if !@ai.trainer.medium_skill?
	if user.pbOwnSide.effects[PBEffects::CheerOffense1] != 0
      multipliers[:power_multiplier] *= 1.5
    end
	if target.pbOwnSide.effects[PBEffects::CheerDefense1] != 0
      multipliers[:power_multiplier] /= 2
    end
  end
end