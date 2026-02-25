#===============================================================================
# * Default ItemHandler
#===============================================================================

ItemHandlers::UseFromBag.add(:CATCHINGCHARM, proc { |item|
  if CharmConfig::ACTIVE_CHARM
    pbToggleCharm(item)
  end
  next 1
})

ItemHandlers::UseFromBag.copy(:CATCHINGCHARM, :EXPCHARM, :OVALCHARM, :SHINYCHARM)