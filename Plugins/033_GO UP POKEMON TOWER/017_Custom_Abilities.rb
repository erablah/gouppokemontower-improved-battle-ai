#===============================================================================
# Custom Ability: EERIECHILL (섬뜩한냉기)
# - Ice-type moves are super effective against Fire and Ghost types
#===============================================================================

# super effectiveness vs Fire/Ghost
Battle::AbilityEffects::DamageCalcFromUser.add(:EERIECHILL,
  proc { |ability, user, target, move, mults, power, type|
    next if type != :ICE
    # Super effective vs Fire: Ice normally does 0.5x to Fire, need 2x → multiply by 4
    # Super effective vs Ghost: Ice normally does 1x to Ghost, need 2x → multiply by 2
    target.pbTypes(true).each do |t|
      case t
      when :FIRE  then mults[:final_damage_multiplier] *= 4
      when :GHOST then mults[:final_damage_multiplier] *= 2
      end
    end
  }
)

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
