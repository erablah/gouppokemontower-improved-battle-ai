#===============================================================================
# Custom Ability: EERIECHILL (섬뜩한냉기)
# - Ice-type moves are super effective against Fire and Ghost types
# Uses pbCalcTypeModSingle override so SE text/sound displays correctly
#===============================================================================

class Battle::Move
  alias eeriechill_pbCalcTypeModSingle pbCalcTypeModSingle
  def pbCalcTypeModSingle(moveType, defType, user, target)
    ret = eeriechill_pbCalcTypeModSingle(moveType, defType, user, target)
    if moveType == :ICE && user.hasActiveAbility?(:EERIECHILL)
      if defType == :FIRE || defType == :GHOST
        ret = Effectiveness::SUPER_EFFECTIVE_MULTIPLIER
      end
    end
    return ret
  end
end

# AI type effectiveness awareness for Eerie Chill
class Battle::AI::AIBattler
  alias eeriechill_effectiveness effectiveness_of_type_against_battler
  def effectiveness_of_type_against_battler(type, user = nil, move = nil)
    ret = eeriechill_effectiveness(type, user, move)
    if type == :ICE && user&.has_active_ability?(:EERIECHILL)
      battler.pbTypes(true).each do |defend_type|
        if (defend_type == :FIRE || defend_type == :GHOST) &&
           !Effectiveness.super_effective_type?(type, defend_type)
          # Undo the original calc for this type and apply SE instead
          original = Effectiveness.calculate(type, defend_type)
          ret = ret / original * Effectiveness::SUPER_EFFECTIVE_MULTIPLIER
        end
      end
    end
    return ret
  end
end

#===============================================================================
# Custom Ability: IRONSKIN (아이언스킨)
# - Normal-type moves become Steel-type with 1.2x power boost
# (Same mechanic as Pixilate/Aerilate/Refrigerate/Galvanize)
#===============================================================================

Battle::AbilityEffects::ModifyMoveBaseType.add(:IRONSKIN,
  proc { |ability, user, move, type|
    next if type != :NORMAL || !GameData::Type.exists?(:STEEL)
    move.powerBoost = true
    next :STEEL
  }
)

Battle::AbilityEffects::DamageCalcFromUser.copy(:AERILATE, :IRONSKIN)

#===============================================================================
# Custom Ability: GRUDGECANDLE (미움불꽃)
# - Absorbs Dark-type moves (immune) and raises Speed by 1 stage
#===============================================================================

Battle::AbilityEffects::MoveImmunity.add(:GRUDGECANDLE,
  proc { |ability, user, target, move, type, battle, show_message|
    next target.pbMoveImmunityStatRaisingAbility(user, move, type,
       :DARK, :SPEED, 1, show_message)
  }
)
