#===============================================================================
# Raid Boss Difficulty & ALS Fix (Final Version)
# - FIX: NameError & NoMethodError (undefined method `totalhp=').
# - Adds raid boss check method.
# - Prevents ALS from scaling Raid Boss levels.
# - Applies final 10x HP Boost after all scaling is complete.
#===============================================================================

#-------------------------------------------------------------------------------
# 1. Pokemon 클래스 확장: 레이드 보스 확인 헬퍼 메서드 추가
#-------------------------------------------------------------------------------
class Pokemon
  # @hp_level 속성을 통해 레이드 보스 여부를 확인합니다.
  def is_raid_boss?
    return defined?(@hp_level) && @hp_level > 0
  end
end

#-------------------------------------------------------------------------------
# 2. ALS 우회 로직: Wild Pokemon 생성 이벤트 핸들러 추가
#    - 레이드 보스인 경우 ALS가 레벨 조정을 시도하는 것을 막습니다.
#-------------------------------------------------------------------------------
EventHandlers.add(:on_wild_pokemon_created, :raid_boss_als_override,
  proc { |pokemon|
    # 레이드 보스인 경우 ALS의 레벨/능력치 조정 로직을 완전히 건너뛰도록 합니다.
    next if pokemon.is_raid_boss? 
  }
)

#-------------------------------------------------------------------------------
# 3. RaidBattle 클래스 확장: HP 덮어쓰기 최종 해결 로직 (Aliasing)
#    - RaidBattle.generate_raid_foe를 가로채서 HP를 최종 부스팅합니다.
#-------------------------------------------------------------------------------
class RaidBattle
  class << self
    # RaidBattle의 클래스 메서드 self.generate_raid_foe를 Aliasing합니다.
    alias raid_als_fix_generate_raid_foe generate_raid_foe
  end

  # Aliasing된 메서드를 재정의합니다.
  def self.generate_raid_foe(pkmn, rules)
    # 1. 기존 generate_raid_foe 로직을 호출하여 보스 포켓몬을 생성합니다.
    boss = raid_als_fix_generate_raid_foe(pkmn, rules) 
    
    # 🌟 2. 최종 HP 부스팅 로직 (모든 덮어쓰기가 끝난 후 마지막 조정)
    if boss.is_raid_boss?
      multiplier = 2 # 10배 추가 부스팅
      
      # FIX: totalhp= 대신 인스턴스 변수 @totalhp와 @hp를 직접 사용하여 값을 할당합니다.
      # 이 방법은 포켓몬 객체의 내부 상태를 직접 수정하여 NoMethodError를 해결합니다.
      
      # 현재 totalhp 및 hp 값을 가져와서 multiplier를 곱한 후 직접 할당합니다.
      boss.instance_variable_set(:@totalhp, boss.totalhp * multiplier)
      boss.instance_variable_set(:@hp, boss.hp * multiplier)
    end
    
    # 3. 최종 보스 포켓몬 객체를 반환합니다.
    return boss
  end
end