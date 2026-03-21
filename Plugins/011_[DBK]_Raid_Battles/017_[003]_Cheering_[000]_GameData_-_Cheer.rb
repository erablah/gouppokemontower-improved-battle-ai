#===============================================================================
# Game data for cheers.
#===============================================================================
module GameData
  class Cheer
    attr_reader :id
    attr_reader :real_name
	attr_reader :icon_position
    attr_reader :command_index
    attr_reader :mode
    attr_reader :cheer_text
	attr_reader :description

    DATA = {}
    
    extend ClassMethodsSymbols
    include InstanceMethods

    def self.load; end
    def self.save; end

    def initialize(hash)
      @id            = hash[:id]
      @real_name     = hash[:name]          || "Unnamed"
	  @icon_position = hash[:icon_position] || 0
	  @command_index = hash[:command_index] || -1
      @mode          = hash[:mode]          || 0
      @cheer_text    = hash[:cheer_text]    || ""
	  @description   = hash[:description]
    end

    def name;        return _INTL(@real_name);   end
    def cheer_text;  return _INTL(@cheer_text);  end
	
	def description(level)
	  return _INTL("") if !@description
	  return @description[level]
	end
    
    def self.get_cheer_for_index(index, mode = 0)
      cheer = self.get(:None)
	  self.each do |c|
        next if c.command_index != index
        cheer = c if c.mode == 0
		if c.mode == mode
		  cheer = c
		  break
		end
      end
      return cheer
    end
  end
end

#===============================================================================

GameData::Cheer.register({
  :id              => :None,
  :name            => _INTL("없음")
})

GameData::Cheer.register({
  :id              => :Offense,
  :name            => _INTL("공격 응원"),
  :icon_position   => 1,
  :command_index   => 0,
  :cheer_text      => _INTL("전력을 다한다!"),
  :description     => [_INTL("응원 레벨 1 이상 필요하다."),
                       _INTL("아군 팀이 기술로 더 많은 피해를 입힌다."),
                       _INTL("아군 팀 기술의 위력이 증가한다."),
                       _INTL("아군 팀 기술이 배리어를 뚫을 수 있다.")]
})

GameData::Cheer.register({
  :id              => :Defense,
  :name            => _INTL("방어 응원"),
  :icon_position   => 2,
  :command_index   => 1,
  :cheer_text      => _INTL("버텨낸다!"),
  :description     => [_INTL("응원 레벨 1 이상 필요하다."),
                       _INTL("아군 팀이 기술로 받는 피해가 줄어든다."),
                       _INTL("아군 팀이 기술 효과에 면역이 된다."),
                       _INTL("아군 팀이 기술 피해를 견뎌낸다.")]
})

GameData::Cheer.register({
  :id              => :Healing,
  :name            => _INTL("회복 응원"),
  :icon_position   => 3,
  :command_index   => 2,
  :cheer_text      => _INTL("회복한다!"),
  :description     => [_INTL("응원 레벨 1 이상 필요하다."),
                       _INTL("아군 팀의 HP를 조금 회복한다."),
                       _INTL("아군 팀의 HP를 회복하고 상태이상을 치료한다."),
                       _INTL("아군 팀에게 소원을 걸고 HP를 완전히 회복한다.")]
})

GameData::Cheer.register({
  :id              => :Counter,
  :name            => _INTL("반격 응원"),
  :icon_position   => 4,
  :command_index   => 3,
  :cheer_text      => _INTL("판세를 뒤집는다!"),
  :description     => [_INTL("응원 레벨 1 이상 필요하다."),
                       _INTL("양 팀의 능력치 변화를 역전시킨다."),
                       _INTL("양 진영의 필드 효과를 서로 바꾼다."),
                       _INTL("양 팀의 힐 블록을 제거하고 적용한다.")]
})

GameData::Cheer.register({
  :id              => :BasicRaid,
  :name            => _INTL("일반 레이드 응원"),
  :icon_position   => 5,
  :command_index   => 3,
  :mode            => 1,
  :cheer_text      => _INTL("힘내자!"),
  :description     => [_INTL("응원 레벨 2 이상 필요하다."),
                       _INTL("응원 레벨 2 이상 필요하다."),
                       _INTL("레이드 턴 카운터를 연장시킨다."),
                       _INTL("레이드 턴과 기절 카운터를 연장시킨다.")]
})

GameData::Cheer.register({
  :id              => :UltraRaid,
  :name            => _INTL("울트라 레이드 응원"),
  :icon_position   => 6,
  :command_index   => 3,
  :mode            => 2,
  :cheer_text      => _INTL("Z파워를 사용하자!"),
  :description     => [_INTL("응원 레벨 MAX 필요하다."),
                       _INTL("응원 레벨 MAX 필요하다."),
                       _INTL("응원 레벨 MAX 필요하다."),
                       _INTL("Z기술을 사용할 수 있게 된다.")]
})

GameData::Cheer.register({
  :id              => :MaxRaid,
  :name            => _INTL("맥스 레이드 응원"),
  :icon_position   => 7,
  :command_index   => 3,
  :mode            => 3,
  :cheer_text      => _INTL("다이맥스하자!"),
  :description     => [_INTL("응원 레벨 MAX 필요하다."),
                       _INTL("응원 레벨 MAX 필요하다."),
                       _INTL("응원 레벨 MAX 필요하다."),
                       _INTL("다이맥스를 사용할 수 있게 된다.")]
})

GameData::Cheer.register({
  :id              => :TeraRaid,
  :name            => _INTL("테라 레이드 응원"),
  :icon_position   => 8,
  :command_index   => 3,
  :mode            => 4,
  :cheer_text      => _INTL("테라스탈하자!"),
  :description     => [_INTL("응원 레벨 MAX 필요하다."),
                       _INTL("응원 레벨 MAX 필요하다."),
                       _INTL("응원 레벨 MAX 필요하다."),
                       _INTL("테라스탈을 사용할 수 있게 된다.")]
})