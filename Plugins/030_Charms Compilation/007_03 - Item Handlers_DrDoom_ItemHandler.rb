#===============================================================================
# * DrDoom ItemHandler
#===============================================================================

ItemHandlers::UseFromBag.add(:APRICORNCHARM, proc { |item|
  if CharmConfig::ACTIVE_CHARM
    pbToggleCharm(item)
  end
  next 1
})

ItemHandlers::UseFromBag.copy(:APRICORNCHARM, :BALANCECHARM, :CLOVERCHARM, :COINCHARM, :COLORCHARM, :CONTESTCHARM,
                              :CRAFTINGCHARM, :DISABLECHARM, :FRUGALCHARM, :GOLDCHARM, :HEALINGCHARM, :HEARTCHARM,
                              :IVCHARM, :KEYCHARM, :LINKCHARM, :LURECHARM, :MERCYCHARM, :MININGCHARM, :PROMOCHARM,
                              :ROAMINGCHARM, :SAFARICHARM, :SMARTCHARM, :SPIRITCHARM, :STABCHARM, :TRADINGCHARM,
                              :TRIPTRIADCHARM, :TWINCHARM, :VIRALCHARM, :TOKENCHARM)

ItemHandlers::UseFromBag.add(:NATURECHARM, proc { |item|
  pbOpenNatureCharm
  next 1
})

ItemHandlers::UseFromBag.add(:WISHINGCHARM, proc { |item|
  pbWishingStar
  next 1
})