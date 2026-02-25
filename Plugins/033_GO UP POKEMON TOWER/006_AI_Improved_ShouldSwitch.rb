#===============================================================================
# 5. ShouldSwitch Handlers
#===============================================================================

Battle::AI::Handlers::ShouldSwitch.add(:high_damage_from_foe,
  proc { |battler, reserves, ai, battle|
    next false
  }
)
