#===============================================================================
# * Tech ItemHandler
#===============================================================================

ItemHandlers::UseFromBag.add(:BERRYCHARM, proc { |item|
  if CharmConfig::ACTIVE_CHARM
    pbToggleCharm(item)
  end
  next 1
})

ItemHandlers::UseFromBag.copy(:BERRYCHARM, :SLOTCHARM)