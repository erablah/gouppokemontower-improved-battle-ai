#===============================================================================
# Global variable to store the chosen type during the Challenge.
#===============================================================================
class PokemonGlobalMetadata
  attr_accessor :monotype
end

#-----------------------------------------------------------------------------
# Sets the given variable to the ID number of the type used in the run.
# Only change 'varnum' if this is causing conflicts.
#-----------------------------------------------------------------------------
def pbSetMonoVariables(varnum)
  $game_variables[varnum] = GameData::Type.get($PokemonGlobal.monotype).id_number
end

# Returns true if a monotype run is active
def pbMonoActive?
  return true if $PokemonGlobal.monotype
end

# Turns off monotype run
def pbEndMono
  $PokemonGlobal.monotype = nil
end

def pbChooseMono
  type_names  = []   # 표시용 이름
  type_ids    = []   # 실제 타입 ID (:FIRE)

  GameData::Type.each do |type|
    next if type.pseudo_type
    next if type.id == :STELLAR        # ← 여기! STELLAR 제외
    type_names.push(type.real_name)
    type_ids.push(type.id)
  end

  type_names.push(_INTL("취소"))

  # 플레이어 선택
  choice_index = pbMessage(
    _INTL("어떤 타입 챌린지에 도전할까?"),
    type_names,
    type_names.length
  )

  # 취소 선택 → 모노타입 OFF, 변수 0
  if choice_index == type_names.length - 1
    $PokemonGlobal.monotype = nil
    $game_variables[100] = 0
    return
  end

  # 선택한 타입
  chosen_type_id = type_ids[choice_index]

  # 글로벌 저장
  $PokemonGlobal.monotype = chosen_type_id

  # 숫자 저장 (1부터 시작)
  $game_variables[100] = choice_index + 1
end


#-----------------------------------------------------------------------------
# Module to check this Pokémom's types and to ensure that only the chosen type 
# is capturable or can evolve into the chosen type.
#-----------------------------------------------------------------------------
module GameData
  class Species
    # Adapted from Pokemon class
    # @return [Array<Symbol>] an array of this Pokémon's types
#=begin

	def mc_types
	  #species_data = GameData::Species.get_species_form(@species, form_simple)
      return species_data.types.clone
	  #ret.push(self.types[1]) if self.types[1] != self.types[0]
      #return ret
    end
alias mc_types types

=begin
    # this don't work and cause "Stack level too deep" error.
    def types
      ret = self.types[0]
      ret.push(self.types[1]) if self.types[1] != self.types[0]
      return ret
    end
=end
 
    # @param type [Symbol, String, Integer] type to check
    # @return [Boolean] whether this Pokémon has the specified type
    def hasType?(type)
      type = GameData::Type.get(type).id
      return self.types.include?(type)
    end
    # New utilities:
    def can_evolve_into_usable?(type, exclude_invalid = true)
      @evolutions.each do |evo|
        next if evo[3]   # Is the prevolution
        next if evo[1] == :None && exclude_invalid
        species = GameData::Species.get(evo[0])
        return true if species.usable_monotype?(type)
      end
      return false
    end
    
  
    def usable_monotype?(type = $PokemonGlobal.monotype)
      return true if type == nil
      return true if self.hasType?(type)
      return true if self.can_evolve_into_usable?(type) && Settings::PREVOS_INCLUDED
      return false
    end
  
  end
end
  
#===============================================================================
# The core method that performs evolution checks. Needs a block given to it,
# which will provide either a GameData::Species ID (the species to evolve
# into) or nil (keep checking).
#===============================================================================
class Pokemon
 
  # @return [Symbol, nil] the ID of the species to evolve into
  def check_evolution_internal
    return nil if egg? || shadowPokemon?
    return nil if hasItem?(:EVERSTONE)
    return nil if hasAbility?(:BATTLEBOND)
    species_data.get_evolutions(true).each do |evo|   # [new_species, method, parameter, boolean]
      next if evo[3]   # Prevolution
      species = GameData::Species.get(evo[0])
      next if !species.usable_monotype?
      ret = yield self, evo[0], evo[1], evo[2]   # pkmn, new_species, method, parameter
      return ret if ret
    end
    return nil
  end
 
  def usable_monotype?(type = $PokemonGlobal.monotype)
    return GameData::Species.get_species_form(self.species, self.form).usable_monotype?
  end
end

#-----------------------------------------------------------------------------
# Giving Pokémon to the player (will send to storage if party is full)
#-----------------------------------------------------------------------------
def pbAddPokemon(pkmn, level = 1, see_form = true)
  return false if !pkmn
  if pbBoxesFull?
    pbMessage(_INTL("There's no more room for Pokémon!"))
    pbMessage(_INTL("The Pokémon Boxes are full and can't accept any more!"))
    return false
  end
  pkmn = Pokemon.new(pkmn, level) if !pkmn.is_a?(Pokemon)
  if !pkmn.usable_monotype?
    type = GameData::Type.get($PokemonGlobal.monotype).real_name
    pbMessage(_INTL("#{pkmn.speciesName},은,는] #{type} 타입 챌린지에서 사용할 수 없다."))
    return false
  end
  species_name = pkmn.speciesName
  pbMessage(_INTL("\\j[{1},은,는] \\j[{2},을,를] 얻었다!\\me[Pkmn get]\\wtnp[80]", $player.name, species_name))
  pbNicknameAndStore(pkmn)
  $player.pokedex.register(pkmn) if see_form
  return true
end

def pbAddPokemonSilent(pkmn, level = 1, see_form = true)
  return false if !pkmn || pbBoxesFull?
  pkmn = Pokemon.new(pkmn, level) if !pkmn.is_a?(Pokemon)
  return false if !pkmn.usable_monotype?
  $player.pokedex.register(pkmn) if see_form
  $player.pokedex.set_owned(pkmn.species)
  pkmn.record_first_moves
  if $player.party_full?
    $PokemonStorage.pbStoreCaught(pkmn)
  else
    $player.party[$player.party.length] = pkmn
  end
  return true
end

#-----------------------------------------------------------------------------
# Giving Pokémon/eggs to the player (can only add to party)
#-----------------------------------------------------------------------------
def pbAddToParty(pkmn, level = 1, see_form = true)
  return false if !pkmn || $player.party_full?
  pkmn = Pokemon.new(pkmn, level) if !pkmn.is_a?(Pokemon)
  if !pkmn.usable_monotype?
    type = GameData::Type.get($PokemonGlobal.monotype).real_name
    pbMessage(_INTL("\\j[#{pkmn.speciesName},은,는] #{type} 타입 챌린지에서 사용할 수 없다."))
    return false
  end
  species_name = pkmn.speciesName
  pbMessage(_INTL("\\j[{1},은,는] \\j[{2},을,를] 얻었다!\\me[Pkmn get]\\wtnp[80]", $player.name, species_name))
  pbNicknameAndStore(pkmn)
  $player.pokedex.register(pkmn) if see_form
  return true
end

def pbAddToPartySilent(pkmn, level = nil, see_form = true)
  return false if !pkmn || $player.party_full?
  pkmn = Pokemon.new(pkmn, level) if !pkmn.is_a?(Pokemon)
  return false if !pkmn.usable_monotype?
  $player.pokedex.register(pkmn) if see_form
  $player.pokedex.set_owned(pkmn.species)
  pkmn.record_first_moves
  $player.party[$player.party.length] = pkmn
  return true
end

def pbAddForeignPokemon(pkmn, level = 1, owner_name = nil, nickname = nil, owner_gender = 0, see_form = true)
  return false if !pkmn || $player.party_full? || !pkmn.usable_monotype?
  pkmn = Pokemon.new(pkmn, level) if !pkmn.is_a?(Pokemon)
  if !pkmn.usable_monotype?
    type = GameData::Type.get($PokemonGlobal.monotype).real_name
    pbMessage(_INTL("#{pkmn.speciesName},은,는] #{type} 타입 챌린지에서 사용할 수 없다."))
    return false
  end
  # Set original trainer to a foreign one
  pkmn.owner = Pokemon::Owner.new_foreign(owner_name || "", owner_gender)
  # Set nickname
  pkmn.name = nickname[0, Pokemon::MAX_NAME_SIZE] if !nil_or_empty?(nickname)
  # Recalculate stats
  pkmn.calc_stats
  if owner_name
    pbMessage(_INTL("\\me[Pkmn get]\\j[{1},은,는] {2}에게서 포켓몬을 받았다.\\wtnp[80]", $player.name, owner_name))
  else
    pbMessage(_INTL("\\me[Pkmn get]\\j[{1},은,는] 포켓몬을 받았다.\\wtnp[80]", $player.name))
  end
  pbStorePokemon(pkmn)
  $player.pokedex.register(pkmn) if see_form
  $player.pokedex.set_owned(pkmn.species)
  return true
end

def pbGenerateEgg(pkmn, text = "")
  return false if !pkmn || $player.party_full?
  pkmn = Pokemon.new(pkmn, Settings::EGG_LEVEL) if !pkmn.is_a?(Pokemon)
  if !pkmn.usable_monotype?
    type = GameData::Type.get($PokemonGlobal.monotype).real_name
    pbMessage(_INTL("#{pkmn.speciesName},은,는] #{type} 타입 챌린지에서 사용할 수 없다."))
    return false
  end
  # Set egg's details
  pkmn.name           = _INTL("알")
  pkmn.steps_to_hatch = pkmn.species_data.hatch_steps
  pkmn.obtain_text    = text
  pkmn.calc_stats
  # Add egg to party
  $player.party[$player.party.length] = pkmn
  return true
end

alias pbAddEgg pbGenerateEgg
alias pbGenEgg pbGenerateEgg


def pbStartTrade(pokemonIndex, newpoke, nickname, trainerName, trainerGender = 0)
  myPokemon = $player.party[pokemonIndex]
  #opponent = NPCTrainer.new(trainerName, trainerGender)
  #opponent.id = $player.make_foreign_ID
  yourPokemon = nil
  resetmoves = true
  if newpoke.is_a?(Pokemon)
    #newpoke.owner = Pokemon::Owner.new_from_trainer(opponent)
	newpoke.owner = Pokemon::Owner.new_foreign(trainerName, trainerGender)
    yourPokemon = newpoke
    resetmoves = false
  else
    species_data = GameData::Species.try_get(newpoke)
    raise _INTL("Species {1} does not exist.", newpoke) if !species_data
    yourPokemon = Pokemon.new(species_data.id, myPokemon.level)
	yourPokemon.owner = Pokemon::Owner.new_foreign(trainerName, trainerGender)
  end
  if !yourPokemon.usable_monotype?
    pbMessage(_INTL("#{pkmn.speciesName},은,는] #{type} 타입 챌린지에서 사용할 수 없다."))
    return false
  end
  yourPokemon.name          = nickname
  yourPokemon.obtain_method = 2   # traded
  yourPokemon.reset_moves if resetmoves
  yourPokemon.record_first_moves
  $player.pokedex.register(yourPokemon)
  $player.pokedex.set_owned(yourPokemon.species)
  pbFadeOutInWithMusic do
    evo = PokemonTrade_Scene.new
    evo.pbStartScreen(myPokemon, yourPokemon, $player.name, trainerName)
    evo.pbTrade
    evo.pbEndScreen
  end
  $player.party[pokemonIndex] = yourPokemon
end

#=============================================================================
# Obedience check - A pokemon that don't have the chosen type won't obey the player
# even if they have all the Badges.- DISABLED FOR NOW.
# This also ins't wotking for wathever reason, so ignore it. players can't 
# get Pokemon from other Types anyway.
#=============================================================================
=begin
class Battle::Battler
  # Return true if Pokémon continues attacking (although it may have chosen to
  # use a different move in disobedience), or false if attack stops.
  
   def usable_monotype?(type = $PokemonGlobal.monotype)
    return GameData::Species.get_species_form(self.species, self.form).usable_monotype?
  end
  
  #alias mc_pbObedienceCheck? pbObedienceCheck?
  def pbObedienceCheck?(choice)
    return true if usingMultiTurnAttack?
    return true if choice[0] != :UseMove
    return true if !@battle.internalBattle
    return true if !@battle.pbOwnedByPlayer?(@index)
	return true if  @battle.usable_monotype?(@index)
    disobedient = false
	type = GameData::Type.get($PokemonGlobal.monotype).real_name
    # Pokémon may be disobedient; calculate if it is
    badge_level = 10 * (@battle.pbPlayer.badge_count + 1)
    badge_level = GameData::GrowthRate.max_level if @battle.pbPlayer.badge_count >= 8
    if Settings::ANY_HIGH_LEVEL_POKEMON_CAN_DISOBEY ||
       (Settings::FOREIGN_HIGH_LEVEL_POKEMON_CAN_DISOBEY && @pokemon.foreign?(@battle.pbPlayer))
      if @level > badge_level
        a = ((@level + badge_level) * @battle.pbRandom(256) / 256).floor
        disobedient |= (a >= badge_level)
      end
    end
	if !@battle.usable_monotype?
        @battle.pbDisplay(_INTL("{1} refuses to Obey! as it does not have the #{type} Typing.", pbThis))
        return false
    end
    disobedient |= !pbHyperModeObedience(choice[2])
    return true if !disobedient
    # Pokémon is disobedient; make it do something else
    return pbDisobey(choice, badge_level)
  end

alias mc_pbDisobey pbDisobey
  def mc_pbDisobey(choice, badge_level)
    move = choice[2]
    PBDebug.log("[Disobedience] #{pbThis} disobeyed")
    @effects[PBEffects::Rage] = false
    # Do nothing if using Snore/Sleep Talk
    if @status == :SLEEP && move.usableWhenAsleep?
      @battle.pbDisplay(_INTL("{1} ignored orders and kept Sleeping!", pbThis))
      return false
    end
    b = ((@level + badge_level) * @battle.pbRandom(256) / 256).floor
    # Use another move
    if b < badge_level
      @battle.pbDisplay(_INTL("{1} ignored Orders!", pbThis))
      return false if !@battle.pbCanShowFightMenu?(@index)
      otherMoves = []
      eachMoveWithIndex do |_m, i|
        next if i == choice[1]
        otherMoves.push(i) if @battle.pbCanChooseMove?(@index, i, false)
      end
      return false if otherMoves.length == 0   # No other move to use; do nothing
      newChoice = otherMoves[@battle.pbRandom(otherMoves.length)]
      choice[1] = newChoice
      choice[2] = @moves[newChoice]
      choice[3] = -1
      return true
    end
    c = @level - badge_level
    r = @battle.pbRandom(256)
    # Fall asleep
    if r < c && pbCanSleep?(self, false)
      pbSleepSelf(_INTL("{1} began to nap!", pbThis))
      return false
    end
    # Hurt self in confusion
    r -= c
    if r < c && @status != :SLEEP
      pbConfusionDamage(_INTL("{1} won't Obey! It Hurt itself in its Confusion!", pbThis))
      return false
    end
    # Show refusal message and do nothing
    case @battle.pbRandom(5)
    when 0 then @battle.pbDisplay(_INTL("{1} won't Obey!", pbThis))
    when 1 then @battle.pbDisplay(_INTL("{1} Turned Away!", pbThis))
    when 2 then @battle.pbDisplay(_INTL("{1} is Loafing Around!", pbThis))
    when 3 then @battle.pbDisplay(_INTL("{1} Pretended not to Notice!", pbThis))
	when 4 then @battle.pbDisplay(_INTL("{1} does not have the #{type} Typing!", pbThis))
    end
    return false
  end
 end
=end
 #=============================================================================
 # SwitchIn in Battle - If the pokemon don't have the chosen Type, it can't be 
 # used in Battle.
 # ...
 # I'M GOING INSANE FIXING IT, will fix it later. don't remove the comments.
 #=============================================================================
=begin
class Battle
  
 #alias mc_pbCanSwitchIn? pbCanSwitchIn?
    def pbCanSwitchIn?(idxBattler, idxParty, partyScene = nil)
    return true if idxParty < 0
    party = pbParty(idxBattler)
	type = GameData::Type.get(type = $PokemonGlobal.monotype).real_name
    return false if idxParty >= party.length
    return false if !party[idxParty]
    if party[idxParty].egg?
      partyScene&.pbDisplay(_INTL("An Egg can't battle!"))
      return false
    end
    if !pbIsOwner?(idxBattler, idxParty)
      if partyScene
        owner = pbGetOwnerFromPartyIndex(idxBattler, idxParty)
        partyScene.pbDisplay(_INTL("You can't switch {1}'s Pokémon with one of yours!", owner.name))
      end
      return false
    end
	if !party[idxParty].usable_monotype?
      partyScene&.pbDisplay(_INTL("{1} refuses to Switch In! as it does not have the #{type} Typing.", party[idxParty].name))
      return false
    end
    if party[idxParty].fainted?
      partyScene&.pbDisplay(_INTL("{1} has no energy left to battle!", party[idxParty].name))
      return false
    end
    if pbFindBattler(idxParty, idxBattler)
      partyScene&.pbDisplay(_INTL("{1} is already in battle!", party[idxParty].name))
      return false
    end
    return true
  end
  
  def pbCanSwitch?(idxBattler, idxParty = -1, partyScene = nil)
    # Check whether party Pokémon can switch in
    return false if !pbCanSwitchIn?(idxBattler, idxParty, partyScene)
	return false if !usable_monotype?(idxBattler, idxParty, partyScene)
    # Make sure another battler isn't already choosing to switch to the party
    # Pokémon
    allSameSideBattlers(idxBattler).each do |b|
      next if choices[b.index][0] != :SwitchOut || choices[b.index][1] != idxParty
      partyScene&.pbDisplay(_INTL("{1} has already been selected.",
                                  pbParty(idxBattler)[idxParty].name))
      return false
    end
    # Check whether battler can switch out
    return pbCanSwitchOut?(idxBattler, partyScene)
  end

  def pbCanChooseNonActive?(idxBattler)
    pbParty(idxBattler).each_with_index do |_pkmn, i|
      return true if pbCanSwitchIn?(idxBattler, i)
    end
    return false
  end

  def pbRegisterSwitch(idxBattler, idxParty)
    return false if !pbCanSwitch?(idxBattler, idxParty) && !usable_monotype?
    @choices[idxBattler][0] = :SwitchOut
    @choices[idxBattler][1] = idxParty   # Party index of Pokémon to switch in
    @choices[idxBattler][2] = nil
    return true
  end
 end
=end
#====================================================================================