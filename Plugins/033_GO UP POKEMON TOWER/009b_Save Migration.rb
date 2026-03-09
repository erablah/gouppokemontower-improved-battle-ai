#===============================================================================
# 구버전 세이브 데이터 마이그레이션
# 이전: $game_variables[149] (밴 리스트), $game_variables[150] (파티 저장소)
# 현재: $PokemonGlobal.tower_banned_families, $PokemonGlobal.tower_party_storage
# $game_variables[148] = 마이그레이션 버전 (0=미완료, CURRENT_MIGRATION_VERSION=최신)
#===============================================================================
MIGRATION_FLAG_VARIABLE    = 148
OLD_PARTY_STORAGE_VARIABLE = 150
OLD_BANNED_FAMILY_VARIABLE = 149

CURRENT_MIGRATION_VERSION = 2

def pbMigrateTowerSaveData
  return if !$PokemonGlobal
  version = $game_variables[MIGRATION_FLAG_VARIABLE] || 0
  return if version >= CURRENT_MIGRATION_VERSION
  migrated = false
  silent = false

  # --- v1: 파티 저장소 마이그레이션 ---
  if version < 1
    old_storage = $game_variables[OLD_PARTY_STORAGE_VARIABLE]
    if old_storage.is_a?(Array) && !old_storage.empty? && $PokemonGlobal.tower_party_storage.nil?
      if old_storage.length < MAX_PARTY_SLOTS
        old_storage += Array.new(MAX_PARTY_SLOTS - old_storage.length) { [] }
      end
      $PokemonGlobal.tower_party_storage = old_storage
      $game_variables[OLD_PARTY_STORAGE_VARIABLE] = 0
      migrated = true
    end

    # --- 밴 리스트 마이그레이션 ---
    old_bans = $game_variables[OLD_BANNED_FAMILY_VARIABLE]
    if old_bans.is_a?(Array) && !old_bans.empty? && $PokemonGlobal.tower_banned_families.nil?
      if old_bans[0].is_a?(Array)
        new_bans = old_bans
      else
        # 플랫 배열 (구버전): 슬롯 0에 전부 할당
        new_bans = Array.new(10) { [] }
        new_bans[0] = old_bans.dup
      end
      if new_bans.length < 10
        new_bans += Array.new(10 - new_bans.length) { [] }
      end
      $PokemonGlobal.tower_banned_families = new_bans
      $game_variables[OLD_BANNED_FAMILY_VARIABLE] = 0
      migrated = true
    end

    # --- 저장소는 있지만 밴 리스트가 없는 경우 재구축 ---
    if $PokemonGlobal.tower_party_storage.is_a?(Array) && $PokemonGlobal.tower_banned_families.nil?
      $PokemonGlobal.tower_banned_families = Array.new(10) { [] }
      $PokemonGlobal.tower_party_storage.each_with_index do |party, idx|
        next if idx >= 10 || !party.is_a?(Array) || party.empty?
        TowerParty.ban_party_family(party, idx)
      end
      migrated = true
    end
  end

  # --- v2: 팔로잉 포켓몬 이벤트 참조 정리 ---
  # 구버전에서 start_following으로 볼 이벤트를 팔로워로 등록했기 때문에,
  # 맵 재진입/리로드 시 해당 이벤트가 erase되는 문제 수정
  if version < 2
    if $game_switches[3]
      $game_temp.followers.remove_follower_by_name("FollowingPkmn")
      migrated = true
      silent = true
    else
      max_version = 1  # switch 3이 꺼져 있으면 v2를 건너뛰고 다음에 재시도
    end
  end

  $game_variables[MIGRATION_FLAG_VARIABLE] = max_version || CURRENT_MIGRATION_VERSION

  if migrated && !silent
    pbMessage("세이브 데이터가 최신 버전으로 업데이트되었습니다.")
  end
end

EventHandlers.add(:on_enter_map, :tower_save_migration,
  proc { |_old_map_id|
    pbMigrateTowerSaveData
  }
)
