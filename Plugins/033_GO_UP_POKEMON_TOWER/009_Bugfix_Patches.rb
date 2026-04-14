# map event bug fixes


#===============================================================================
# Fix: Game_Character wait_start uses System.uptime which resets on game launch.
# If a character was saved mid-wait, wait_start will be from a previous session
# and the wait condition (System.uptime - wait_start < wait_count) can never
# be satisfied, permanently freezing the character.
#===============================================================================
class Game_Character
  alias _fix_stale_wait_update_command update_command
  def update_command
    if @wait_count > 0 && @wait_start && @wait_start > System.uptime
      @wait_start = System.uptime
    end
    _fix_stale_wait_update_command
  end
end

#===============================================================================#
# Can only change speed in battle during command phase (delta speed up overridden by battle AI improved)
#===============================================================================#
class Battle
  alias_method :original_pbCommandPhase, :pbCommandPhase unless method_defined?(:original_pbCommandPhase)
  def pbCommandPhase
    $CanToggle = true
    original_pbCommandPhase
    $CanToggle = false
  end
end