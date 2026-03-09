#===============================================================================
# Multi-Slot Party Storage System (10 Slots)
#===============================================================================
MAX_PARTY_SLOTS            = 11
HALL_OF_FAME_FILE          = "TowerHallOfFame.rxdata"
#===============================================================================

#===============================================================================
# Hall of Fame 기록 저장
#===============================================================================
module TowerHallOfFame
  def self.load
    return [] unless File.exist?(HALL_OF_FAME_FILE)
    data = load_data(HALL_OF_FAME_FILE)
    return [] unless data.is_a?(Array)
    return data
  end

  def self.save(party_record)
    records = self.load
    records << party_record
    save_data(records, HALL_OF_FAME_FILE)
  end
end

def pbRecordTowerHallOfFame
  record = $player.party.map { |pkmn| pkmn.clone }
  TowerHallOfFame.save(record)
end

#===============================================================================
# Hall of Fame UI 출력
#===============================================================================
def pbShowTowerHallOfFame
  records = TowerHallOfFame.load
  if records.empty?
    pbMessage("아직 도전 기록이 없습니다.")
    return
  end

  original_data  = $PokemonGlobal.hallOfFame ? $PokemonGlobal.hallOfFame.clone : []
  original_count = $PokemonGlobal.hallOfFameLastNumber

  $PokemonGlobal.hallOfFame = records.clone
  $PokemonGlobal.hallOfFameLastNumber = records.length

  pbHallOfFamePC

  $PokemonGlobal.hallOfFame = original_data
  $PokemonGlobal.hallOfFameLastNumber = original_count
end

#===============================================================================
# 파티 저장 / 불러오기 / 삭제
#===============================================================================
module BattlePartyStorage
  def self.init_storage
    data = $PokemonGlobal.tower_party_storage
    if !data.is_a?(Array) || data.length < MAX_PARTY_SLOTS
      data = Array.new(MAX_PARTY_SLOTS) { [] }
    end
    $PokemonGlobal.tower_party_storage = data
  end

  def self.save_party(slot)
    init_storage
    idx = slot - 1
    party = $player.party
    return pbMessage("파티가 비어 있어 저장할 수 없습니다.") if party.empty?

    cloned = party.map { |pkmn| pkmn.clone }
    $PokemonGlobal.tower_party_storage[idx] = cloned

	unless idx == 10   # 0~10 인덱스 중 10 = 11번 슬롯
	  TowerParty.ban_party_family(party, idx)
	end
    pbRecordTowerHallOfFame

  end

  def self.load_party(slot)
    init_storage
    idx = slot - 1
    stored = $PokemonGlobal.tower_party_storage[idx]
    return pbMessage("#{slot}번 슬롯에는 저장된 파티가 없습니다.") if !stored || stored.empty?

    $player.party.clear
    stored.each { |pkmn| $player.party << pkmn.clone }

    pbMessage("#{slot}번 슬롯의 파티를 불러왔습니다.")
  end

  def self.clear_slot(slot)
    init_storage
    idx = slot - 1
    $PokemonGlobal.tower_party_storage[idx] = []
    TowerParty.clear_banned_families(idx) unless idx == 10
  end

  def self.clear_all
    init_storage
    $PokemonGlobal.tower_party_storage = Array.new(MAX_PARTY_SLOTS) { [] }
    $PokemonGlobal.tower_banned_families = Array.new(10) { [] }
    save_data([], HALL_OF_FAME_FILE) if File.exist?(HALL_OF_FAME_FILE)
  end
end

def pbSavePartySlot(slot);  BattlePartyStorage.save_party(slot);  end
def pbLoadPartySlot(slot);  BattlePartyStorage.load_party(slot);  end
def pbClearPartySlot(slot); BattlePartyStorage.clear_slot(slot); end
def pbClearAllPartySlots;   BattlePartyStorage.clear_all;         end

#===============================================================================
# 밴 시스템
#===============================================================================
module TowerParty
  # 2D array: index 0-9 corresponds to slots 1-10
  def self.init_banned_families
    val = $PokemonGlobal.tower_banned_families
    if !val.is_a?(Array) || val.length < 10 || !val[0].is_a?(Array)
      val = Array.new(10) { [] }
      $PokemonGlobal.tower_banned_families = val
    end
    return val
  end

  def self.banned_families
    init_banned_families
    return $PokemonGlobal.tower_banned_families
  end

  def self.all_banned_families
    families = []
    banned_families.each do |slot_families|
      next unless slot_families.is_a?(Array)
      families.concat(slot_families)
    end
    return families.uniq
  end

  def self.species_banned?(species)
    family = GameData::Species.get(species).get_baby_species
    return all_banned_families.include?(family)
  end

  def self.filter_party_by_ban(party)
    return party.reject { |pkmn| species_banned?(pkmn.species) }
  end

  def self.ban_party_family(party, slot_index)
    init_banned_families
    slot_families = $PokemonGlobal.tower_banned_families[slot_index] || []
    party.each do |pkmn|
      family = GameData::Species.get(pkmn.species).get_baby_species
      next if slot_families.include?(family)
      slot_families << family
    end
    $PokemonGlobal.tower_banned_families[slot_index] = slot_families
  end

  def self.clear_banned_families(slot_index)
    init_banned_families
    $PokemonGlobal.tower_banned_families[slot_index] = []
  end

  def self.clean_party!
    $player.party.delete_if { |p| species_banned?(p.species) }
  end

  # 파티를 적으로 불러와 싸우는 배틀
	def self.battle(slot, trainer_type, trainer_name, trainer_version = 0)
	  stored = $PokemonGlobal.tower_party_storage
	  return pbMessage("파티 저장소가 초기화되어 있지 않습니다.") unless stored.is_a?(Array)

	  enemy_stored = stored[slot]
	  return pbMessage("#{slot + 1}번 슬롯에는 저장된 파티가 없습니다.") unless enemy_stored.is_a?(Array) && !enemy_stored.empty?

	  # ★★★ slot 11은 밴 체크 없이 그대로 파티 사용 ★★★
	  if slot != 10   # slot 인덱스는 0~10 → 11번 슬롯 = index 10
		usable = filter_party_by_ban($player.party)
		if usable.empty?
		  pbMessage("사용 가능한 포켓몬이 없습니다!")
		  return false
		end
		$player.party = usable
	  end

	  enemy_party = enemy_stored.map { |p| p.clone }
	  trainer_data = GameData::Trainer.get(trainer_type, trainer_name, trainer_version)
	  trainer = trainer_data.to_trainer
	  trainer.party = enemy_party

	  return TrainerBattle.start(trainer)
	end
	
  def self.banned?(pkmn)
    return false if !pkmn
    if species_banned?(pkmn.species)
      return true
    end
    return false
  end
end


#===============================================================================
# 스타터 포켓몬 선택 (밴 체크 포함)
#===============================================================================
def pbTowerStarterPokemon(species, level = 5)
  species_name = GameData::Species.get(species).name
  form_name = GameData::Species.get(species).form_name
  full_name = form_name && !form_name.empty? ? "#{form_name} #{species_name}" : species_name
  # 밴 체크
  if TowerParty.species_banned?(species)
    pbMessage("\\j[\\c[3]#{species_name}\\c[0],은,는] 사용할 수 없습니다.")
    return false
  end
  # 선택 확인
  if !pbConfirmMessage("\\j[\\c[3]#{full_name}\\c[0],을,를] 데려갈까요?")
    return false
  end
  # 포켓몬 추가
  pbSEPlay("Pkmn get")
  _tower_pbAddPokemon(species, level)
  $game_switches[3] = false
  $game_variables[7] = 1
  $game_self_switches[[$game_map.map_id, @event_id, "A"]] = true
  $game_switches[82] = true
  $game_map.need_refresh = true
  FollowingPkmn.start_following(16)
  pbMessage("\\xn[\\c[3]오박사\\c[0]]위로 올라가서 도전을 시작하시길 바랍니다!")
  return true
end

#===============================================================================
# 일반 포켓몬 추가 차단
#===============================================================================
alias _tower_pbAddPokemon pbAddPokemon
def pbAddPokemon(*args)
  # args[0] = species, args[1] = level 등
  # 새 포켓몬 객체를 생성해서 밴 검사
  species = args[0]
  if TowerParty.species_banned?(species)
    return false
  end
  return _tower_pbAddPokemon(*args)
end

alias _tower_pbAddPokemonSilent pbAddPokemonSilent
def pbAddPokemonSilent(*args)
  species = args[0]
  if TowerParty.species_banned?(species)
    return false
  end
  return _tower_pbAddPokemonSilent(*args)
end


alias _tower_pbAddToParty pbAddToParty
def pbAddToParty(*args)
  pkmn = args[0]
  if TowerParty.banned?(pkmn)
    return false
  end
  return _tower_pbAddToParty(*args)
end


#===============================================================================
# Battle: Safe pbRecordAndStoreCaughtPokemon for TowerParty bans
#===============================================================================
class Battle
  # 고유 alias 이름으로 기존 원본 메서드 안전하게 저장
  unless method_defined?(:_safe_pbRecordAndStoreCaughtPokemon_original)
    alias_method :_safe_pbRecordAndStoreCaughtPokemon_original, :pbRecordAndStoreCaughtPokemon
  end

  def pbRecordAndStoreCaughtPokemon
    # 1. @caughtPokemon 존재 체크
    if @caughtPokemon && @caughtPokemon.is_a?(Array)
      # 2. 밴된 포켓몬 제거
      @caughtPokemon.reject! do |pkmn|
        if TowerParty.banned?(pkmn)
          pbDisplayPaused("\\j[#{pkmn.name},은,는] 이전 회차에 사용한 포켓몬이라 포획되지 않았습니다!")
          true
        else
          false
        end
      end
    end

    # 3. 원본 메서드 안전하게 호출
    if defined?(_safe_pbRecordAndStoreCaughtPokemon_original)
      _safe_pbRecordAndStoreCaughtPokemon_original
    end
  end
end



#===============================================================================
# Essentials의 파티 객체(PokemonParty)에 대해 addPokemonSilent 차단 적용
#===============================================================================
# NOTE: Removed PokemonParty patch because Essentials v21.1 has no addPokemonSilent.
# Ban-checking is now handled only through pbAddPokemon / pbAddPokemonSilent / pbAddToParty hooks.

#===============================================================================
# Tower Hall of Fame Scene
#===============================================================================
def pbShowTowerHallOfFame
  storage = $PokemonGlobal.tower_party_storage

  # 현재 저장된 파티만 불러오기
  records = []
  if storage.is_a?(Array)
    storage.each do |party|
      next if !party.is_a?(Array) || party.empty?
      records << party.map { |pkmn| pkmn.clone }
    end
  end

  # 저장된 파티가 없다면 메시지 출력
  if records.empty?
    pbMessage("현재 저장된 파티가 없습니다.")
    return
  end

  # 기존 명예의 전당 데이터 백업
  original_data  = $PokemonGlobal.hallOfFame ? $PokemonGlobal.hallOfFame.clone : []
  original_count = $PokemonGlobal.hallOfFameLastNumber

  # Hall of Fame UI에서 보이도록 구조 구성
  $PokemonGlobal.hallOfFame = records.clone
  $PokemonGlobal.hallOfFameLastNumber = records.length

  # Essentials 기본 명예의 전당 UI 실행
  pbHallOfFamePC

  # 종료 후 되돌리기
  $PokemonGlobal.hallOfFame = original_data
  $PokemonGlobal.hallOfFameLastNumber = original_count
end



#===============================================================================
# 포켓몬 스프라이트 파일명 가져오기 (ArgumentError 해결을 위한 단순화)
#===============================================================================

class PokemonGlobalMetadata
  attr_accessor :lobby_pokemon_talk
  attr_accessor :tower_party_storage
  attr_accessor :tower_banned_families

  # initialize를 덮어쓰지 않고, alias를 사용하여 안전하게 확장합니다.
  unless method_defined?(:_tower_global_metadata_initialize_alias)
    alias_method :_tower_global_metadata_initialize_alias, :initialize
  end

  def initialize
    _tower_global_metadata_initialize_alias # 원본 initialize 호출
    @lobby_pokemon_talk = nil # 새로운 변수를 nil로 초기화
    @tower_party_storage = nil
    @tower_banned_families = nil
  end
end
#===============================================================================
# 포켓몬 스프라이트 파일명 가져오기 (PBS 내부 이름 및 폼 기반)
#===============================================================================
def pbGetPokemonCharset(pkmn)
  # 1. 포켓몬의 종 데이터를 가져옵니다.
  species_data = GameData::Species.get(pkmn.species)
  
  # 2. PBS에 저장된 내부 이름(Internal Name)을 가져옵니다.
  # 예: :PIKACHU => "PIKACHU"
  filename = species_data.species.to_s
  
  # 3. 폼이 0보다 큰 경우 폼 번호를 추가합니다.
  # 예: "RAICHU_1"
  if pkmn.form > 0
    filename += "_#{pkmn.form}"
  end
  
  # 4. 파일명 반환 (대문자 형태 유지)
  return filename
end
#===============================================================================
# 랜덤 포켓몬 로비톡 (소환/설정 로직)
# - 맵에 들어올 때 '자동 실행' 이벤트에서 한 번 호출되어야 합니다.
#===============================================================================
POKEMON_LOBBY_EVENT = 4

def pbPokemonLobbyTalk
  event = $game_map.events[POKEMON_LOBBY_EVENT]
  return unless event

  # 1. 이미 소환된 포켓몬이 있는지 확인 (nil이 아니거나, 스프라이트가 설정되어 있다면)
  # 포켓몬이 이미 소환되어 있다면, 로직을 중단하고 현재 포켓몬을 유지합니다.
  if $PokemonGlobal.lobby_pokemon_talk.is_a?(Hash) && event.character_name != ""
    return
  end
  
  # 2. 저장된 파티 데이터 가져오기 및 유효성 검사
  BattlePartyStorage.init_storage
  stored_parties = $PokemonGlobal.tower_party_storage
  
  valid_slots = []
  if stored_parties.is_a?(Array)
    stored_parties.each_with_index do |party, index|
      if party.is_a?(Array) && !party.empty?
        valid_slots << { slot: index + 1, party: party }
      end
    end
  end

  # 저장된 파티가 없는 경우 (캐릭터 숨김)
  if valid_slots.empty?
    event.character_name = ""
    event.refresh
    $PokemonGlobal.lobby_pokemon_talk = nil
    return
  end
  
  # *PWT의 randLobbyGeneration처럼 소환 확률을 적용할 수 있습니다.
  # return if rand(100) < 25 # 25% 확률로 아무도 소환 안 함

  # 3. 랜덤 파티 및 포켓몬 선택
  chosen_slot_data = valid_slots.sample
  slot_number      = chosen_slot_data[:slot]
  chosen_party     = chosen_slot_data[:party]
  chosen_pokemon   = chosen_party.sample
  
  pkmn_charset = pbGetPokemonCharset(chosen_pokemon) # PBS 내부 이름 기반 함수
  
  # 4. 로비 이벤트 설정
  event.character_name = "Followers/#{pkmn_charset}"
  event.refresh # 스프라이트 즉시 반영 (캐릭터 출력)
  
  # 이벤트에 커스텀 대사 정보 저장
  $PokemonGlobal.lobby_pokemon_talk = { 
    name: chosen_pokemon.name, 
    slot: slot_number 
  }
end

#===============================================================================
# 로비 이벤트 상호작용 함수 (대화 로직 + 울음소리 추가 - 에러 해결)
#===============================================================================
def pbStartPokemonLobbyTalk
  talk_data = $PokemonGlobal.lobby_pokemon_talk
  
  event = $game_map.events[POKEMON_LOBBY_EVENT]
  
  if talk_data.nil? || event.character_name == ""
    pbMessage("... 이곳은 텅 비어 있습니다.")
    return
  end
  
  # 1. 저장된 포켓몬 정보 가져오기
  slot_num = talk_data[:slot]
  
  # 2. 저장된 파티 슬롯에서 포켓몬 객체를 다시 불러옵니다.
  BattlePartyStorage.init_storage
  stored_parties = $PokemonGlobal.tower_party_storage
  
  party_index = slot_num - 1
  
  if !stored_parties.is_a?(Array) || !stored_parties[party_index].is_a?(Array) || stored_parties[party_index].empty?
    pbMessage("저장된 파티 정보를 불러올 수 없습니다.")
    return
  end
  
  chosen_party = stored_parties[party_index]
  
  pokemon_name = talk_data[:name]
  pkmn_to_cry = chosen_party.find { |pkmn| pkmn.name == pokemon_name }
  
  if pkmn_to_cry.nil?
    pkmn_to_cry = chosen_party.first
  end

# 3. 울음소리 출력 (정확한 함수 경로 명시)
  if pkmn_to_cry.is_a?(Pokemon)
    # 함수가 GameData 모듈 내부에 정의되어 있으므로, 해당 경로를 명시하여 호출합니다.
    # 만약 에러 발생 시 GameData::Species.play_cry 대신
    # GameData::Pokemon.play_cry 로 바꿔서 시도해 보세요.
    GameData::Species.play_cry(pkmn_to_cry) 
  end
  
  # 4. 메세지 출력
  pokemon_name = talk_data[:name]
  slot_num     = talk_data[:slot]
  
  # 4. 메세지 출력
  pbMessage(_INTL("{1}회차에 같이 타워에 오른 \\j[{2},이,가] 당신의 방에 놀러왔다!", slot_num, pokemon_name))
end

#-------------------------------------------------------------------------------
# Pokemon 클래스 확장: 저장된 파티의 진화 계열에 속하는지 확인 (밴 목록 데이터 활용)
#-------------------------------------------------------------------------------
class Pokemon
  # 현재 포켓몬이 저장된 파티의 포켓몬과 같은 진화 계열에 속하는지 확인
  def in_stored_party?
    return false if !defined?(TowerParty)
    current_family = GameData::Species.get(self.species).get_baby_species
    return TowerParty.all_banned_families.include?(current_family)
  end
end

#-------------------------------------------------------------------------------
# Battle::Scene::PokemonDataBox 확장: 파티 아이콘 표시 (사용자 코드 그대로 유지)
#-------------------------------------------------------------------------------
class Battle::Scene::PokemonDataBox < Sprite
  
  # 1. icon_party를 그리는 새로운 메서드 정의
  def draw_party_icon
    return if !@battler.opposes?(0) # 적 포켓몬에게만 표시
    
    # 수정된 in_stored_party?를 사용하여 파티 등록 여부 확인
    return if !@battler.pokemon || !@battler.pokemon.in_stored_party? 
    
    # icon_own의 크기를 32x32로 가정하고 그 오른쪽에 8픽셀 간격으로 배치
    icon_width = 32
    party_icon_x = @spriteBaseX + 8 + icon_width + 8 
    
    # Graphics/UI/Battle/icon_party 파일을 사용합니다.
    pbDrawImagePositions(self.bitmap, [["Graphics/UI/Battle/icon_party", party_icon_x - 21, 34]])
  end
  
  # 2. 기존 refresh 메서드를 Aliasing하여 확장하고, draw_party_icon을 호출
  
  # 기존 refresh 메서드 이름을 alias_method로 백업합니다.
  alias party_icon_fix_refresh refresh unless method_defined?(:party_icon_fix_refresh)

  def refresh
    # 기존 refresh 로직 실행 (draw_owned_icon 포함 모든 UI 요소 그리기)
    party_icon_fix_refresh 
    
    # 🌟 아이콘 표시 메서드를 호출하여 화면에 그립니다.
    draw_party_icon
  end
end

