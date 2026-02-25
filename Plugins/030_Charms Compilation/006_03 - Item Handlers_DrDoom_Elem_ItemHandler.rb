#===============================================================================
# * DrDoom Elemental ItemHandler
#===============================================================================

ItemHandlers::UseFromBag.add(:BUGCHARM, proc { |item|
  if CharmConfig::ACTIVE_CHARM
    pbToggleCharm(item)
  end
  next 1
})

ItemHandlers::UseFromBag.copy(:BUGCHARM, :DARKCHARM, :DRAGONCHARM, :ELECTRICCHARM, :FAIRYCHARM, :FIGHTINGCHARM,
                              :FIRECHARM, :FLYINGCHARM, :GHOSTCHARM, :GRASSCHARM, :GROUNDCHARM, :ICECHARM,
                              :NORMALCHARM, :POISONCHARM, :PSYCHICCHARM, :ROCKCHARM, :STEELCHARM, :WATERCHARM)