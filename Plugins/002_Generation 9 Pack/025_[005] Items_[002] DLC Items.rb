################################################################################
# 
# DLC item handlers.
# 
################################################################################

#===============================================================================
# Health Mochi
#===============================================================================
ItemHandlers::UseOnPokemonMaximum.copy(:HPUP, :HEALTHMOCHI)
ItemHandlers::UseOnPokemon.copy(:HPUP, :HEALTHMOCHI)

#===============================================================================
# Muscle Mochi
#===============================================================================
ItemHandlers::UseOnPokemonMaximum.copy(:PROTEIN, :MUSCLEMOCHI)
ItemHandlers::UseOnPokemon.copy(:PROTEIN, :MUSCLEMOCHI)

#===============================================================================
# Resist Mochi
#===============================================================================
ItemHandlers::UseOnPokemonMaximum.copy(:IRON, :RESISTMOCHI)
ItemHandlers::UseOnPokemon.copy(:IRON, :RESISTMOCHI)

#===============================================================================
# Genius Mochi
#===============================================================================
ItemHandlers::UseOnPokemonMaximum.copy(:CALCIUM, :GENIUSMOCHI)
ItemHandlers::UseOnPokemon.copy(:CALCIUM, :GENIUSMOCHI)

#===============================================================================
# Clever Mochi
#===============================================================================
ItemHandlers::UseOnPokemonMaximum.copy(:ZINC, :CLEVERMOCHI)
ItemHandlers::UseOnPokemon.copy(:ZINC, :CLEVERMOCHI)

#===============================================================================
# Swift Mochi
#===============================================================================
ItemHandlers::UseOnPokemonMaximum.copy(:CARBOS, :SWIFTMOCHI)
ItemHandlers::UseOnPokemon.copy(:CARBOS, :SWIFTMOCHI)

#===============================================================================
# Fresh-Start Mochi
#===============================================================================
ItemHandlers::UseOnPokemon.add(:FRESHSTARTMOCHI, proc { |item, qty, pkmn, scene|
  next false if pkmn.ev.values.none? { |ev| ev > 0 }
  GameData::Stat.each_main { |s| pkmn.ev[s.id] = 0 }
  pkmn.changeHappiness("vitamin")
  pkmn.calc_stats
  pbSEPlay("Use item in party")
  scene.pbRefresh
  scene.pbDisplay(_INTL("{1}의 모든 능력치 포인트가 0으로 돌아갔다!", pkmn.name))
  next true
})

#===============================================================================
# Fairy Feather
#===============================================================================
Battle::ItemEffects::DamageCalcFromUser.copy(:PIXIEPLATE, :FAIRYFEATHER)

#===============================================================================
# Wellspring Mask, Hearthflame Mask, Cornerstone Mask
#===============================================================================
Battle::ItemEffects::DamageCalcFromUser.add(:WELLSPRINGMASK,
  proc { |item, user, target, move, mults, power, type|
    mults[:final_damage_multiplier] *= 1.2 if user.isSpecies?(:OGERPON)
  }
)

Battle::ItemEffects::DamageCalcFromUser.copy(:WELLSPRINGMASK, :HEARTHFLAMEMASK, :CORNERSTONEMASK)


#===============================================================================
# Meteorite
#===============================================================================
ItemHandlers::UseOnPokemon.add(:METEORITE, proc { |item, qty, pkmn, scene|
  if !pkmn.isSpecies?(:DEOXYS)
    scene.pbDisplay(_INTL("It had no effect."))
    next false
  elsif pkmn.fainted?
    scene.pbDisplay(_INTL("This can't be used on the fainted Pokémon."))
    next false
  end
  choices = [
    _INTL("노말폼"),
    _INTL("어택폼"),
    _INTL("디펜스폼"),
    _INTL("스피드폼"),
    _INTL("Cancel")
  ]
  new_form = scene.pbShowCommands(_INTL("테오키스를 어떤 폼으로 바꿀까요?", pkmn.name), choices, pkmn.form)
  if new_form == pkmn.form
    scene.pbDisplay(_INTL("It won't have any effect."))
    next false
  elsif new_form > -1 && new_form < choices.length - 1
    pkmn.setForm(new_form) do
      scene.pbRefresh
      scene.pbDisplay(_INTL("{1}의 모습이 변했다!", pkmn.name))
    end
    next true
  end
  next false
})