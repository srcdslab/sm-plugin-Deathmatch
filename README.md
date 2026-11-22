# Deathmatch

SourceMod plugin for Counter-Strike: Source that turns any map into a team deathmatch: instant
respawn, random spawn points, a weapon menu and spawn protection.

Written for 64-bit CS:S servers: pure SourcePawn, no extension. It only uses SourceMod's own
`cstrike` natives and forwards (`CS_RespawnPlayer`, `CS_OnTerminateRound`, `CS_TerminateRound`,
`CS_OnBuyCommand`), whose gamedata ships with SourceMod for `linux` and `linux64`.

## How it works

- **Respawn**: a dead player respawns after `sm_dm_respawn_time`. A new player respawns once he has
  picked a team and a model.
- **No round end**: the round never ends when a team is wiped out or when the round time runs out.
  "Game commencing" still restarts the round. When `mp_timelimit` is reached, the plugin fires a
  `game_end` entity: scoreboard for `mp_chattime`, then the next map. If the map has not changed
  after `mp_chattime` + 15 s, the plugin forces the change. With `sm_dm_round_timer_map_time 1` the HUD
  round timer shows the map time left.
- **Random spawns**: on each spawn the player is moved to a point of
  `configs/deathmatch/spawns/<map>.cfg`. The plugin skips points that are blocked or that an
  enemy can see, and points closer to an enemy than `sm_dm_spawn_min_distance`. If no point passes
  every check, it uses the best one it found. Without a file for the map, players use the map's
  own spawns.
- **Weapons**: the weapon menu offers *New weapons*, *Same weapons*, *Same weapons every time* and
  *Random weapons*. The choice is saved in client preferences. `!guns` brings the menu back. Bots get
  random weapons. AWPs are limited per team with `sm_dm_awp_limit`. Buying is disabled.
- **Spawn protection**: the player takes no damage for `sm_dm_spawn_protection` seconds and is drawn
  half transparent. Protection ends early as soon as he fires.
- **Cleanup**: dropped weapons are removed after `sm_dm_dropped_weapon_lifetime`. Bomb sites,
  hostages and rescue zones are removed (`sm_dm_remove_objectives`), and C4 is taken away on spawn.

## Installation

Extract the release archive matching your SourceMod version (`-sm1.12` or `-sm1.13`) into `cstrike/`:

- `addons/sourcemod/plugins/Deathmatch.smx`
- `addons/sourcemod/translations/Deathmatch.phrases.txt`
- `addons/sourcemod/configs/deathmatch/spawns/*.cfg`

The config `cfg/sourcemod/plugin.Deathmatch.cfg` is created on first load.

Recommended game settings: `mp_freezetime 0`, `mp_timelimit 20`, `mp_roundtime 9`,
`mp_autoteambalance 1`, `mp_limitteams 1`, `mp_friendlyfire 0`.

## Spawn points

`configs/deathmatch/spawns/de_dust2.cfg` ships 60 points generated from the map's navigation mesh.
The generator keeps the largest flat walkable areas, at least 300 units apart, and turns each point
toward its most open direction.

Admins with the `config` flag can edit the points in game:

| Command | Description |
| - | - |
| `sm_dm_spawn_show` | Draw every point for 10 seconds |
| `sm_dm_spawn_add` | Add a point at your position, facing your view direction |
| `sm_dm_spawn_remove` | Remove the point closest to you (within 128 units) |
| `sm_dm_spawn_save` | Write the points to the map's file |
| `sm_dm_spawn_reload` | Reload the map's file |

## Player commands

| Command | Description |
| - | - |
| `sm_guns`, `sm_weapons` | Show the weapon menu again |

## Cvars

| Cvar | Default | Description |
| - | - | - |
| `sm_dm_enable` | `1` | Enable deathmatch |
| `sm_dm_respawn_time` | `1.5` | Seconds before a dead player respawns |
| `sm_dm_spawn_protection` | `2.0` | Seconds of spawn protection, `0` = off |
| `sm_dm_random_spawns` | `1` | Use the map's spawn point file |
| `sm_dm_spawn_min_distance` | `600` | Preferred minimum distance to the closest enemy |
| `sm_dm_spawn_visibility_check` | `1` | Avoid spawn points an enemy can see |
| `sm_dm_primary_weapons` | `ak47,m4a1,awp,...` | Primary weapons offered |
| `sm_dm_secondary_weapons` | `deagle,usp,glock,p228,fiveseven,elite` | Secondary weapons offered |
| `sm_dm_awp_limit` | `2` | AWPs per team, `-1` = no limit |
| `sm_dm_armor` | `100` | Armor given on spawn |
| `sm_dm_helmet` | `1` | Give a helmet on spawn |
| `sm_dm_hegrenades` | `0` | HE grenades given on spawn |
| `sm_dm_flashbangs` | `0` | Flashbangs given on spawn |
| `sm_dm_smokegrenades` | `0` | Smoke grenades given on spawn |
| `sm_dm_menu_time` | `10` | Seconds after a spawn during which menu picks replace the current weapons |
| `sm_dm_dropped_weapon_lifetime` | `0.1` | Seconds before a dropped weapon is removed, `-1` = never |
| `sm_dm_hp_on_kill` | `0` | Health given to the killer |
| `sm_dm_hp_on_headshot` | `0` | Health given for a headshot kill (instead of `sm_dm_hp_on_kill`) |
| `sm_dm_max_hp` | `100` | Health cap for the kill rewards |
| `sm_dm_remove_objectives` | `1` | Remove bomb sites, hostages and rescue zones |
| `sm_dm_round_timer_map_time` | `1` | Show the map time left in the round timer |
| `sm_dm_give_weapons` | `1` | Give weapons on spawn, offer the weapon menu and block buying; `0` leaves weapons to another plugin such as GunGame |
| `sm_dm_ffa` | `0` | Free for all: every other player counts as an enemy when a spawn point is picked |

## License

GPL-3.0, see [LICENSE](LICENSE).
