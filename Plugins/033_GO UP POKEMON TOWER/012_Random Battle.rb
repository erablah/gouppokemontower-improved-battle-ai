#===============================================================================
# * Z01_RandomTrainerParty (트레이너 포켓몬 랜덤 선택 플러그인)
# * PBS에 6마리를 초과하여 정의된 트레이너의 파티를 랜덤 6마리로 선택합니다.
# * 6마리 이하 트레이너에게는 영향을 주지 않습니다.
#===============================================================================

# GameData::Trainer 로드 시점을 후킹(Hooking)합니다.
# 이 이벤트 핸들러는 TrainerBattle.generate_foes 내부의 pbLoadTrainer 직후에 호출됩니다.

EventHandlers.add(:on_trainer_load, :random_party_selection,
  proc { |trainer|
    # Settings::MAX_PARTY_SIZE는 일반적으로 6입니다.
    max_size = Settings::MAX_PARTY_SIZE

    # 1. 안전장치 (Safety Check)
    # 현재 트레이너가 가진 포켓몬이 6마리를 초과하는지 확인합니다.
    # 6마리 이하의 트레이너에게는 이 로직을 적용하지 않아 기존 작동 방식을 유지합니다.
    if trainer.party.length > max_size
      
      # 2. 랜덤 선정 로직 (Random Selection Logic)
      
      full_party = trainer.party
      
      # 파티를 무작위로 섞고, 앞에서부터 6마리만 선택합니다.
      # Ruby의 Array#shuffle은 배열을 섞고, Array#first(n)은 앞에서 n개를 가져옵니다.
      selected_party = full_party.shuffle.first(max_size)
      
      # 3. 트레이너 객체의 파티를 수정된 파티로 교체합니다.
      # 이 수정된 파티는 Battle.new를 통해 Battle 객체로 전달됩니다.
      trainer.party = selected_party
      
      # 디버그 로그 (선택 사항)
      PBDebug.log_ai("DEBUG: [랜덤 파티] 트레이너 #{trainer.full_name}의 팀이 #{full_party.length}마리에서 랜덤 #{max_size}마리로 변경되었습니다.")
    else
      # 6마리 이하인 경우, 로그만 남기고 아무것도 수정하지 않습니다.
      PBDebug.log_ai("DEBUG: [랜덤 파티] 트레이너 #{trainer.full_name}의 팀은 #{trainer.party.length}마리이므로 랜덤 파티가 적용되지 않았습니다.")
    end
  }
)