#===============================================================================
# * Lin ItemHandler
#===============================================================================

ItemHandlers::UseFromBag.add(:CORRUPTCHARM, proc { |item|
  if CharmConfig::ACTIVE_CHARM
    pbToggleCharm(item)
  end
  next 1
})

ItemHandlers::UseFromBag.copy(:CORRUPTCHARM, :EFFORTCHARM, :FRIENDSHIPCHARM, :GENECHARM,
                              :HERITAGECHARM, :HIDDENCHARM, :POINTSCHARM, :PURECHARM, :STEPCHARM)