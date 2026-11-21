# Play as Slender — Architecture & Technical Design

## 1. Runtime Injection & Engine Constraints

- **Target Engine**: *Slender: The Arrival* (10th Anniversary Edition), Unreal Engine `5.3.0-0+UE5` (Win64 Shipping).
- **Injection Layer**: UE4SS v4.0.0 via `dwmapi.dll` proxy inside `SlenderTheArrival\Binaries\Win64\`.
- **Why `ue4ss\Mods\PlayAsSlender\`**: The game's built-in `SimpleUGC` plugin clears `SlenderTheArrival\Mods\` on startup. Hosting all Lua scripts and assets inside `SlenderTheArrival\Binaries\Win64\ue4ss\Mods\PlayAsSlender\` keeps original `.exe`, `.pak`, `.ucas`, and `.utoc` archives completely unmodified.
- **Persistent Campaign State**: Saved outside the mod payload at `ue4ss\PlayAsSlender_progress.ini` (`unlocked_max=1..9` and `order=...`), preserving player campaign progression across mod updates.

---

## 2. Module Topology (`mod/PlayAsSlender/Scripts/`)

```
main.lua (ExecuteInGameThreadAfterFrames loop, World transition & Travel FSM)
 ├── config.lua                  (Map configs, asset paths, tunables, keybinds.ini loader)
 ├── logger.lua                  (File logger -> ue4ss\PlayAsSlender.log, SafeCall, IsValidObj)
 ├── ue_bridge.lua               (UE 5.3 reflection wrappers, LineTrace/GroundTrace, NavSys, math)
 ├── menu_integration.lua        (Native W_Button_C injection into W_SubMenu_Main + ChapterSelect gating)
 ├── loading_screen_manager.lua  (KismetRenderingLibrary PNG import + GameInstance/LevelInfo overrides)
 ├── progression_manager.lua     (9-chapter campaign progression persistence & order sync)
 ├── slender_controller.lua      (ACharacter spawn, SK_Slender01 mesh/animations, 3D tentacles, collision)
 ├── camera_controller.lua       (3P over-shoulder CameraActor, spring-arm trace, FreeCam)
 ├── slender_abilities.lua       (Q Teleport, E Psychic Dread, F Terrify + Objective Interruption)
 ├── human_visuals.lua           (Survivor AIController possession, ShadowCaster material restoration, PAS_HumanFlashlight)
 ├── objective_manager.lua       (Multi-map objective indexing, exploration zones, blacklist)
 ├── human_navigation.lua        (RecastNavMesh direct pathing OR House BFS + DoorTunnels + 5-ray whiskers)
 ├── human_perception.lua        (Non-omniscient FOV cones, LineTraceSingle occlusion, DangerZones)
 ├── human_fear_system.lua       (Distance/gaze/trauma/stage fear curves, Ambush Shocks, Breakdown timer)
 ├── human_ai_controller.lua     (9-state Survivor FSM, dynamic juking, mobile recovery)
 ├── game_mode_manager.lua       (Hunt Stages I-IV, Win/Loss rules, Hunter Score & Rank S-D)
 └── debug_overlay.lua           (UMG HUD, Predator Sense, Telemetry dossier, End Screen + ui_theme.lua)
```

---

## 3. Core Subsystems

### 3.1. Vanilla Preservation vs. Mod Takeover
- `main.lua` monitors `World` pointer/name changes on every tick.
- In `SlenderMainMenu`, `menu_integration.lua` injects a native `W_Button_C` (`ИГРАТЬ ЗА СЛЕНДЕРА`) into `W_SubMenu_Main`. Clicking it sets `ModArmed = true`, applies custom loading screens, and opens `W_SubMenu_ChapterSelect` with chapter lock states enforced via `progression_manager.lua`.
- Clicking vanilla menu buttons (`Start`, `Chapter Select`, `Extended Chapters`) clears `ModArmed` and restores vanilla `GameInstance` / `LevelInfo` loading screens (`LoadingScreenMgr.RestoreVanilla`), allowing unmodified vanilla play.
- During a modded match, `slender_controller.lua` neutralizes `BP_AISpawner_C` and vanilla enemy Blueprints (`BP_Teleporter_C`, `BP_Chaser_C`, `BP_Charlie*`), while `main.lua` stops intro `LevelSequenceActor` cutscenes.

### 3.2. Slenderman Actor & 3P Camera (`slender_controller.lua`, `camera_controller.lua`)
- Rather than directly possessing `BP_SlenderMan_Forest_C` (whose Blueprint `SlowTick`/`OnScoreChanged` resets positions without an AIController), the mod preloads `SK_Slender01`, `Thriller_Idle_Modified`, `Sad_Walk`, and `SM_Tentacle_01..04`, then spawns a clean `/Script/Engine.Character` with custom capsule collision (`r=42`, `hh=115`), smooth ground-snapping movement, and toggleable 3D back tentacles.
- `camera_controller.lua` drives an isolated `CameraActor` via `SetViewTargetWithBlend`, with spring-arm wall collision (`LineTraceSingle`), `F3` FreeCam support, and omnidirectional non-shadow `PAS_SlenderVisionLight` + camera PostProcess exposure balancing (`V` toggle, ON by default) so Slenderman sees clearly even in unlit interiors without flashlight cones.

### 3.3. Survivor Possession, Textured Mesh, Glitch Suppression & Overhead Bar (`human_visuals.lua`, `debug_overlay.lua`)
- The Survivor pawn is possessed by a clean `/Script/AIModule.AIController` (`PlayerState` is preserved beforehand for `Score` tracking).
- `ShadowCaster` (`sk_laurenshadow` / `sk_charliesdadshadow` / `sk_changeling_boy_shadow`) is unhidden, stripped of `ShadowCaster` override materials, restored with full multi-slot materials, and switched to `LightingChannels.bChannel0 = true` so the Survivor renders fully textured and properly lit.
- **Glitch Suppression & Overhead Health Bar**: `human_fear_system.lua` keeps `survivor.Sanity = 100.0`, while `human_visuals.lua` disables `pawn.PostProcess`, `VisualSanityDrainComponent`, `BP_SpookyGlitch_C`, `FOVShiftCameraModifier`/`LimpLoopModifier`, camera shakes, and glitch scalars in `MPC_UI_ScreenEffect` so Slenderman's screen stays glitch-free even when approaching or catching the Survivor. `ue_bridge.lua` (`ProjectWorldToWidget`) and `debug_overlay.lua` (`UpdateSurvivorHealthBar`) render a native-styled health bar directly above the Survivor's head on every tick with line-of-sight visibility filtering.
- **Camera-Flashlight Isolation**: `BP_ProjectXCharacter` and `BP_WeaponInstanceFlashlight_C` synchronize the stock `pawn.Flashlight` and `FirstPersonFollowComponent` to `GetPlayerCameraManager(0)` — which in Play-as-Slender mode points at Slenderman's 3P `CameraActor`. To guarantee the flashlight stays exclusively with the Survivor across all chapters (including `Level06_Escape` and `Level03_IntoTheAbyss`), `human_visuals.lua` permanently mutes/hides `pawn.Flashlight`, disables `WeaponComponent` / `FirstPersonFollowComponent` / `FirstPersonCameraComponent` ticks, creates a mod-owned `SpotLightComponent` (`PAS_HumanFlashlight`) attached to the Survivor's `CapsuleComponent`, and actively scans/silences any stray `SpotLightComponent` near Slenderman or `CameraActor` every tick cycle.

### 3.4. Dual Navigation & Non-Omniscient AI (`objective_manager.lua`, `human_navigation.lua`, `human_perception.lua`, `human_ai_controller.lua`)
- **Non-Omniscient Perception**: The Survivor discovers objectives (`PAGE_VISION_RANGE = 1750 cm`) and detects Slenderman (`SLENDER_VISION_RANGE = 4500 cm`, `116°` primary FOV, `72°` peripheral glimpse, `360 cm` Sixth Sense) strictly via `LineTraceSingle` occlusion checks. Sightings create decaying `DangerZones` that influence A* / BFS route costs.
- **NavMesh Maps** (`Level02_TheEightPages`, `Level09_Genesis`, `Level03_IntoTheAbyss`, etc.): Direct `NavigationSystemV1` pathfinding (`FindPathToLocationSynchronously`) + danger-detour graph routing.
- **Non-NavMesh Indoor/House Maps** (`Level01_Prologue`, `Level06_Escape`, etc.): Two-resolution physics-verified BFS flood-fill (`140 cm` indoor / `280 cm` yard) with dual-channel (`Visibility` + `Camera`) shoulder-width clearance traces, 1F window-hugging guards, automatic `BP_DoorBase_C` hinge-offset `DoorTunnel` discovery, AI door opening, 5-ray steering whiskers, and corner-breakout recovery.
- **9-State FSM**: `Exploring`, `Searching`, `Suspicious`, `Investigating`, `Interacting`, `Panicking`, `Escaping` (minimum `5.0 s` commitment + dynamic `90°` lateral juking under `11 m`), `Recovering` (mobile retreat), and `Lost`.

### 3.5. Hunt Escalation, Fear & Match Scoring (`human_fear_system.lua`, `slender_abilities.lua`, `game_mode_manager.lua`)
- **Hunt Stages I–IV**: Collecting objectives escalates the hunt (`STAGE I: STALKING` → `STAGE II: HAUNTING` → `STAGE III: DESPERATION` → `STAGE IV: FINAL HOUR`), scaling passive LOS and Psychic Dread fear rates (`+7%` per stage above Stage I) and announcing transitions in the HUD.
- **Abilities**: `Q` Teleport (LOS pop-in & collision validated), `E` Psychic Dread (fear aura + `25%` faster Terrify recharge when stalking unseen in `8–24 m`), and `F` Terrify (`+22..+32` Fear, plus `+6` bonus Fear & Objective Interruption tracking within `5 m` of uncollected objectives or during `Interacting`).
- **Hunter Score & Rank**: Finalizes end-of-match performance into Ranks `S`–`D` displayed with native `UITheme` gauges (`SANITY SHATTERED`, `OBJECTIVES DENIED`), 2-column camcorder dossier, and native `W_Button_C` post-match actions (`NEXT LEVEL`, `RESTART [F8]`, `MAIN MENU`).
