#===============================================================================
# * Main
#===============================================================================

class Player
  attr_accessor :charmsActive
  attr_accessor :charmList
  attr_accessor :elementCharmList
  attr_accessor :last_wish_time
  attr_accessor :ball_for_apricorn
  attr_accessor :next_run
  attr_accessor :link_charm_data
  attr_accessor :activeNature
  attr_accessor :natureList

  def initializeCharms
    @last_wish_time ||= 0
	#Species, Chain Count, Fled Species/Chain, Placeholder for using an automatic evolution plugin.
	@link_charm_data ||= [0, 0, [], nil]
	@ball_for_apricorn ||= 0
	@next_run ||= 0
	@activeNature ||= []
	@natureList ||= []
    @charmList = [
        :APRICORNCHARM, :BALANCECHARM, :BERRYCHARM, :CATCHINGCHARM, :CLOVERCHARM, :COINCHARM, :COLORCHARM,
        :CONTESTCHARM, :CORRUPTCHARM, :CRAFTINGCHARM, :DISABLECHARM, :EFFORTCHARM, :EXPALLCHARM,
        :EXPCHARM, :FRIENDSHIPCHARM, :FRUGALCHARM, :GENECHARM, :GOLDCHARM, :HEALINGCHARM, :HEARTCHARM,
        :HERITAGECHARM, :HIDDENCHARM, :IVCHARM, :KEYCHARM, :LINKCHARM, :LURECHARM, :MERCYCHARM, :MININGCHARM,
        :NATURECHARM, :OVALCHARM, :POINTSCHARM, :PROMOCHARM, :PURECHARM, :ROAMINGCHARM, :RESISTORCHARM, :SAFARICHARM,
		:SHINYCHARM, :SLOTSCHARM, :SMARTCHARM, :SPIRITCHARM, :STABCHARM, :STEPCHARM, :TRADINGCHARM, :TRIPTRIADCHARM,
		:TWINCHARM, :VIRALCHARM, :WISHINGCHARM
      ]
    @elementCharmList = [
        :BUGCHARM, :DARKCHARM, :DRAGONCHARM, :ELECTRICCHARM, :FAIRYCHARM, :FIGHTINGCHARM,
        :FIRECHARM, :FLYINGCHARM, :GHOSTCHARM, :GRASSCHARM, :GROUNDCHARM, :ICECHARM,
        :NORMALCHARM, :PSYCHICCHARM, :POISONCHARM, :ROCKCHARM, :STEELCHARM, :WATERCHARM
      ]
    @charmsActive = {
    #Default Charms
      :CATCHINGCHARM    => false,
      :EXPCHARM         => false,
      :OVALCHARM        => false,
      :SHINYCHARM       => false,
    #Lin Charms
      :CORRUPTCHARM		=> false,
      :EFFORTCHARM		=> false,
      :FRIENDSHIPCHARM	=> false,
      :GENECHARM		=> false,
      :HERITAGECHARM	=> false,
      :HIDDENCHARM		=> false,
      :POINTSCHARM		=> false,
      :PURECHARM		=> false,
      :STEPCHARM		=> false,
    #Tech Charms
      :BERRYCHARM       => false,
      :SLOTSCHARM       => false,
    #DrDoom Charms
      :APRICORNCHARM    => false,
      :BALANCECHARM     => false,
      :CLOVERCHARM      => false,
      :COINCHARM        => false,
      :COLORCHARM       => false,
      :CONTESTCHARM     => false,
      :CRAFTINGCHARM    => false,
      :DISABLECHARM     => false,
      #:EXPALLCHARM		=> false,
      :FRUGALCHARM      => false,
      :GOLDCHARM        => false,
      :HEALINGCHARM     => false,
      :HEARTCHARM       => false,
      #:ITEMFINDERCHARM  => false,
      :IVCHARM          => false,
      :KEYCHARM         => false,
      :LINKCHARM		=> false,
      :LURECHARM        => false,
      :MERCYCHARM       => false,
      :MININGCHARM      => false,
	  :NATURECHARM		=> false,
      :PROMOCHARM       => false,
      :ROAMINGCHARM     => false,
      :RESISTORCHARM    => false,
      :SAFARICHARM      => false,
      :SMARTCHARM       => false,
      :SPIRITCHARM      => false,
      :STABCHARM		=> false,
      :TRADINGCHARM     => false,
      :TRIPTRIADCHARM   => false,
      :TWINCHARM        => false,
      :VIRALCHARM       => false,
      :WISHINGCHARM     => false,
    #DrDoom Elemental Charms
      :BUGCHARM         => false,
      :DARKCHARM        => false,
      :DRAGONCHARM      => false,
      :ELECTRICCHARM    => false,
      :FAIRYCHARM       => false,
      :FIGHTINGCHARM    => false,
      :FIRECHARM        => false,
      :FLYINGCHARM      => false,
      :GHOSTCHARM       => false,
      :GRASSCHARM       => false,
      :GROUNDCHARM      => false,
      :ICECHARM         => false,
      :NORMALCHARM      => false,
      :PSYCHICCHARM     => false,
      :POISONCHARM      => false,
      :ROCKCHARM        => false,
      :STEELCHARM       => false,
      :WATERCHARM       => false
    }
  end
end

module GameData
  class Item
    def is_charm?
      charms_ids = $player.charmList
      charm = charm_ids.include?(self.id.to_sym)
      return charm
    end

    def is_echarm?
      echarm_ids = $player.elementCharmList
      echarm = echarm_ids.include?(self.id.to_sym)
      return echarm
    end
  end
end

def activeCharm?(charm)
  if CharmConfig::ACTIVE_CHARM
    $player.initializeCharms if !$player.charmsActive
    return $player.charmsActive[charm]
  else
    return $bag.has?(charm)
  end
end

def pbToggleCharm(charm)
  $player.initializeCharms if !$player.charmsActive
  charmData = GameData::Item.get(charm)
  if $player.charmsActive[charm]
    $player.charmsActive[charm] = false
    pbMessage(_INTL("\\j[{1},이,가] 비활성화됐다!", charmData.name))
  else
    pbMessage(_INTL("\\j[{1},이,가] 활성화됐다!", charmData.name))
    pbCheckCharm(charm)
    $player.charmsActive[charm] = true
  end
end

def pbDisableExclusiveCharms(charm1, messageOff, messageOn)
  if $player.activeCharm?(charm1)
    $player.charmsActive[charm1] = false
    pbMessage(_INTL("{2}으로 인해 {2}이 비활성화 되었다!", messageOff, messageOn))
  end
end

def pbDisableAllElementalCharms(source_charm)
  source_name = GameData::Item.get(source_charm).name
  typeCharms = $player.elementCharmList
  typeCharms.each do |charm|
    if $player.charmsActive[charm]
      charm_name = GameData::Item.get(charm).name
      # 메세지를 source_charm(균형의 부적/연결의 부적)에 맞춰 동적으로 출력하도록 수정
      pbMessage(_INTL("{1}이 {2}으로 인해 비활성화 되었다!", charm_name, source_name))
      $player.charmsActive[charm] = false # 기존 type_charm 오타 수정됨
    end
  end
end

def pbDisableElementalCharms(charm)
  charmData = GameData::Item.get(charm)
  typeCharms = $player.elementCharmList
  typeCharms.each do |type_charm|
    next if type_charm == charm
    activeElem = type_charm if $player.charmsActive[type_charm]
    $player.charmsActive[type_charm] = false
  end
  if $player.charmsActive[:BALANCECHARM]
    $player.charmsActive[:BALANCECHARM] = false
    pbMessage(_INTL("균형의 부적이 {1}으로 인해 비활성화 되었다!", charmData.name))
  elsif $player.charmsActive[:LINKCHARM]
    $player.charmsActive[:LINKCHARM] = false
    pbMessage(_INTL("연결의 부적이 {1}으로 인해 비활성화 되었다!.", charmData.name))
  elsif !activeElem.empty?
    pbMessage(_INTL("{2}으로 인해 {2}이 비활성화 되었다!", activeElem.name, charmData.name))
  end
end

def pbCheckCharm(charm)
  typeCharms = $player.elementCharmList
  activeElem = false
  case charm
  when :CORRUPTCHARM
    pbDisableExclusiveCharms(:PURECHARM, "Pure", "Corrupt")
  when :HEARTCHARM
    pbDisableExclusiveCharms(:MERCYCHARM, "Mercy", "Heart")
  when :MERCYCHARM
    pbDisableExclusiveCharms(:HEARTCHARM, "Heart", "Mercy")
  when :PURECHARM
    pbDisableExclusiveCharms(:CORRUPTCHARM, "Corrupt", "Pure")
  when :BALANCECHARM
    pbDisableExclusiveCharms(:LINKCHARM, "Link", "Balance")
    pbDisableAllElementalCharms(:BALANCECHARM)
  when :LINKCHARM
    pbDisableExclusiveCharms(:BALANCECHARM, "Balance", "Link")
    pbDisableAllElementalCharms(:LINKCHARM)
  when typeCharms.include?(charm)
    pbDisableElementalCharms(charm)
  end
end

def pbOpenNatureCharm
  $player.activeNature ||= []  
  $player.natureList = []
  commands = []

  stat_abbreviations = {
    :ATTACK => 'Atk',
    :DEFENSE => 'Def',
    :SPECIAL_ATTACK => 'SpAtk',
    :SPECIAL_DEFENSE => 'SpDef',
    :SPEED => 'Spd',
  }
     
  GameData::Nature.each do |nature_data|
    nature_id = nature_data.id
    nature_name = nature_data.name
    $player.natureList.push(nature_id)
    charm_status = ($player.activeNature == nature_id) ? "Active" : "Inactive"
    stat_changes = nature_data.stat_changes.map { |stat, change| "#{stat_abbreviations[stat]}: #{change}" }.join(", ")
  	stat_changes = "No stat changes." if stat_changes.empty?
 	commands.push(_INTL("{1} ({2}): {3}", nature_name, charm_status, stat_changes))
  end    

  cmd = pbMessage("Choose a Nature.", commands, -1)

  if cmd >= 0
    selected_nature_id = $player.natureList[cmd]
    if $player.activeNature.length > 0 && $player.activeNature == selected_nature_id
      pbMessage(_INTL("{1} Nature was deactivated.", GameData::Nature.get($player.activeNature).name))
      $player.activeNature = []
      return nil
    elsif $player.activeNature.length > 0 && $player.activeNature != selected_nature_id
      pbMessage(_INTL("{1} Nature was deactivated.", GameData::Nature.get($player.activeNature).name))
    end
    $player.activeNature = []
    $player.activeNature = selected_nature_id
    charm_status = (selected_nature_id == $player.activeNature) ? "activated" : "Inactivated"     
 
    pbMessage(
      _INTL("The {1} Nature was {2}.",
      GameData::Nature.get(selected_nature_id).name,
      _INTL(charm_status))
    )
  end
end