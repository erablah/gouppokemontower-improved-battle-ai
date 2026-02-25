#===============================================================================
# * Slot Charm
#===============================================================================

class SlotMachineReel < BitmapSprite
  alias slotcharm_initialize initialize
  def initialize(x, y, reel_num, difficulty = 1)
    slotcharm_initialize(x, y, reel_num, difficulty = 1)
    @spin_speed *= 3/4 if $player.activeCharm?(:SLOTCHARM)
  end

  def stopSpinning(noslipping = false)
    @stopping = true
    @slipping = SLIPPING.sample
    case @difficulty
    when 0   # Easy
      second_slipping = SLIPPING.sample
      @slipping = [@slipping, second_slipping].min
    when 2   # Hard
      second_slipping = SLIPPING.sample
      @slipping = [@slipping, second_slipping].max
    end
    @slipping = 0 if noslipping || $player.activeCharm?(:SLOTCHARM)
  end
end