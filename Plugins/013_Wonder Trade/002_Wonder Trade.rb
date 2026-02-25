#===============================================================================
# Wonder Trade
# By Dr.Doom76
# [TowerParty 밴 시스템 연동 버전]
#===============================================================================

def pbIntroGreeting(trainerGender)
	if trainerGender == 0
		flavor = "\\b"
	else
		flavor = "\\r"
	end
	pbMessage(_INTL("그럼 미라클교환을 시작하겠습니다!", flavor))
	commands = [_INTL("바로 교환하기"), _INTL("설명듣고 교환하기"), _INTL("취소")]
	choice = pbMessage(_INTL("무엇을 하시겠나요?"), commands)
	if choice == 0
		pbMessage(_INTL("알겠습니다. 그럼 바로 시작하겠습니다!", flavor))
	elsif choice == 1
		pbMessage(_INTL("미라클 교환은 당신이 가지고 있는 포켓몬을 누군가와 교환하는 시스템입니다!", flavor))
		pbMessage(_INTL("어떤 포켓몬이 교환될 지 모르니 더 재밌지 않을까요?", flavor))
		pbMessage(_INTL("교환한 포켓몬과 같은 레벨의 포켓몬으로 교환 받을 수 있습니다.", flavor))
		pbMessage(_INTL("단, 전설의 포켓몬 및 환상의 포켓몬은 교환 포켓몬으로 나오지 않습니다!", flavor))
		pbMessage(_INTL("그럼 어떤 포켓몬을 교환할까요?", flavor))
	else
		pbMessage(_INTL("다음에 다시 이용해주세요!", flavor))
	end
	return choice
end


def pbWonderTrade(nickName = nil, trainerName = nil, trainerGender = nil)
  blocklist = WonderTradeSettings::BLOCKLIST_POKEMON
  allowlist = WonderTradeSettings::ALLOWLIST_POKEMON
  chosen = -1
  if rand(100) < 80
    trainerName ||= WonderTradeSettings::MALE_NAMES.sample
	trainerGender ||= 0
  else
    trainerName ||= WonderTradeSettings::FEMALE_NAMES.sample
	trainerGender ||= 1
  end
  
  setArgs = nickName, trainerName, trainerGender
  choice = pbIntroGreeting(trainerGender)
  
  if choice == 0 || choice == 1
    pbFadeOutIn do
      scene = PokemonStorageScene.new
      screen = PokemonStorageScreen.new(scene, $PokemonStorage)
	    @scene.pbMessage(_INTL("미라클교환으로 보낼 포켓몬을 선택해주세요!"))
      chosen = screen.pbWonderTradeFromPC
    end
  
    if chosen.nil?
      pbMessage(_INTL("다음에 다시 이용해주세요!"))
    else
      # Probability for rarity levels
      rarityProb = {
        common: 50,
        uncommon: 25,
        rare: 18,
        veryRare: 5,
        ultraRare: 2,
        legendary: 0
      }
      
      pokemonData = Hash.new(0)
      
	    # Adds allowlist Pokemon into the pool
	    allowlist.each do |species_id, chanceIncrease|
	      chanceIncrease ||= 1
        # ★ TowerParty 밴 체크 (Allowlist)
        next if defined?(TowerParty) && TowerParty.species_banned?(species_id)
	      pokemonData[species_id] += chanceIncrease
      end
	  
      # Cycles through each encounter for map and version
      GameData::Encounter.each do |encounter|
        map = encounter.map
        version = encounter.version
        encounterData = GameData::Encounter.get(map, version)
        
        # If encounter data is found, cycle through them for species encountered
        if encounterData
          encounterData.types.each do |encounterType, speciesList|
            # Cycles through the species encounters to split out enc chance, species, min lvl, max lvl
            speciesList.each do |encounterChance, species, min, max|
		      # Skips blocklisted Pokemon
			      next if blocklist.include?(species)
            # ★ TowerParty 밴 체크 (Encounter List)
            next if defined?(TowerParty) && TowerParty.species_banned?(species)
            # ★ ---------------------------------------
            # Counts the number of times a species is encountered
            pokemonData[species] += 1
          end
        end
      end
    end
    # Sorts the data by the number of times encountered
    sortedPokemonData = pokemonData.sort_by { |species, weight| -weight }
    
    # Splits the data into 6 equal sections, which populate the "rarities"
    rarities = sortedPokemonData.each_slice(sortedPokemonData.size / 6).to_a
    common, uncommon, rare, veryRare, ultraRare, legendary = rarities

    # Generate a random number between 0 and 100
    randomNumber = rand(100)
    
    # Initialize variables
    currentRange = 0
    selectedRarity = nil
    
    # Cycles through the rarity probabilities to find the selected rarity
    rarityProb.each do |rarity, probability|
      currentRange += probability
      if randomNumber < currentRange
        selectedRarity = rarity
        break
      end
    end
    
    selectedRaritySpecies = case selectedRarity
      when :common then common
      when :uncommon then uncommon
      when :rare then rare
      when :veryRare then veryRare
      when :ultraRare then ultraRare
      when :legendary then legendary
      else []
    end
    # Calculate the total weight for the selected rarity
    totalWeightRarity = selectedRaritySpecies.map { |species_id, weight| weight }.sum

    # Generate a random weight for picking rarities
    randomWeightRarity = rand(totalWeightRarity)

    # Initialize variables
    currentWeightRarity = 0
    chosenSpecies = nil

    # Iterate through the selected rarity species to find the chosen species
    selectedRaritySpecies.each do |species_id, weight|
      currentWeightRarity += weight
      if randomWeightRarity < currentWeightRarity
        chosenSpecies = species_id
        break
      end
    end

    if chosenSpecies
      speciesData = GameData::Species.get(chosenSpecies)
      speciesName = speciesData.species
    else
      # 목록이 비었을 경우의 Fallback 로직 추가 (필요하다면)
      speciesName = :PIKACHU # 예시
    end
    
    pbWonderStartTrade(chosen, speciesName, setArgs)
    end
  end
end


def pbWonderStartTrade(chosen, speciesName, setArgs)
  $stats.trade_count += 1

  myPokemon = $PokemonStorage[chosen[0]][chosen[1]]
  resetmoves = true
  trainerName = setArgs[1]
  trainerGender = setArgs[2]

  # 포켓몬 생성 (원본 스펙 + 현재 레벨)
  yourPokemon = Pokemon.new(speciesName, myPokemon.level)

  # --- ALS 자동진화 적용 ---
  begin
    AutomaticLevelScaling.setTemporarySetting("automaticEvolutions", true)
    AutomaticLevelScaling.setTemporarySetting("includePreviousStages", true)
    AutomaticLevelScaling.setTemporarySetting("includeNextStages", true)
    AutomaticLevelScaling.setTemporarySetting("includeNonNaturalEvolutions", true)

    # 레벨에 맞춰 진화 단계 적용
    yourPokemon.scaleEvolutionStage
  ensure
    # 임시 설정 초기화
    AutomaticLevelScaling.resetTemporarySettings if AutomaticLevelScaling.respond_to?(:resetTemporarySettings)
  end
  # --------------------------

  # 닉네임 처리
  yourPokemon.name = setArgs[0]
  if WonderTradeSettings::USE_NICKNAME
    yourPokemon.name = WonderTradeSettings::POKEMON_NICKNAMES.sample if setArgs[0].nil?
  end

  # 소유자 정보 및 초기화
  yourPokemon.owner = Pokemon::Owner.new_foreign(trainerName, trainerGender)
  yourPokemon.obtain_method = 2 # traded
  yourPokemon.reset_moves if resetmoves
  yourPokemon.record_first_moves

  # Charms Case 적용
  if PluginManager.installed?("Charms Case")
    tradingCharmIV = CharmCaseSettings::TRADING_CHARM_IV
    if $player.activeCharm?(:TRADINGCHARM)
      GameData::Stat.each_main do |s|
        stat_id = s.id
        yourPokemon.iv[stat_id] = [yourPokemon.iv[stat_id] + tradingCharmIV, 31].min if yourPokemon.iv[stat_id]
      end
      yourPokemon.shiny = true if rand(100) < CharmCaseSettings::TRADING_CHARM_SHINY
    end
  end

  # 교환 화면
  pbFadeOutInWithMusic do
    evo = PokemonTrade_Scene.new
    evo.pbStartScreen(myPokemon, yourPokemon, $player.name, trainerName)
    evo.pbTrade
    evo.pbEndScreen
  end

  # Storage에 반영
  $PokemonStorage[chosen[0]][chosen[1]] = yourPokemon
end





class PokemonStorageScreen
  def pbWonderTradeFromPC
    $game_temp.in_storage = true
    @heldpkmn = nil
    @scene.pbStartBox(self, 0)
    retval = nil
    loop do
      selected = @scene.pbSelectBox(@storage.party)
      if selected && selected[0] == -3   # Close box
        if pbConfirm(_INTL("Exit from the Box?"))
		  pbMessage(_INTL("Come back if you want to try out the Wonder Trade!"))
          pbSEPlay("PC close")
          break
        end
        next
      end
      if selected.nil?
        next if pbConfirm(_INTL("Continue Box operations?"))
        break
      elsif selected[0] == -4   # Box name
        pbBoxCommands
      else
        pokemon = @storage[selected[0], selected[1]]
        next if !pokemon
        commands = [
          _INTL("교환"),
          _INTL("정보"),
        ]
        commands.push(_INTL("Debug")) if $DEBUG
        commands.push(_INTL("취소"))
        helptext = JosaProcessor.process(_INTL("\\j[{1},이,가] 선택되었습니다.", pokemon.name))
        command = pbShowCommands(helptext, commands)
        case command
        when 0   # Select
			ret = pbConfirmMessage(JosaProcessor.process(_INTL("\\j[{1},을,를] 교환할까요?", pokemon.name)))
            if ret
			  retval = selected
              break
			end
        when 1 # Summary
          pbSummary(selected, nil)
        when 2
          if $DEBUG
            pbPokemonDebug(pokemon, selected)
          end
        end
      end
    end
    @scene.pbCloseBox
    $game_temp.in_storage = false
	# Returns location in PC
    return retval
  end
end