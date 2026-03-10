# map event bug fixes

#===============================================================================
# Fix: Map 67(shopping floor) has a shop-reset NPC event that should be reset when leaving the map.
#===============================================================================
EventHandlers.add(:on_leave_map, :reset_map_self_switches,
  proc { |new_map_id, new_map|
    old_map_id = $game_map.map_id
    if old_map_id == 67
      $game_self_switches[[67, 20, "A"]] = false
    end
  }
)

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
