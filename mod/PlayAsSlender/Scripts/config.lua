-- PlayAsSlender Configuration & Tunables
local Config = {}

Config.TARGET_MAP_TOKEN = "Level02_TheEightPages"
Config.TARGET_MAP_PATH  = "/Game/Maps/Slender/Level02_TheEightPages"
Config.MENU_MAP_TOKEN   = "SlenderMainMenu"

local function DetectModRootDir()
    local ok, src = pcall(function() return debug.getinfo(1, "S").source end)
    if ok and type(src) == "string" then
        src = src:gsub("^@", ""):gsub("/", "\\")
        local root = src:match("^(.*)\\[Ss]cripts\\config%.lua$")
        if root and root ~= "" then
            return root
        end
    end
    return "ue4ss\\Mods\\PlayAsSlender"
end

Config.MOD_ROOT_DIR = DetectModRootDir()

Config.NON_GAMEPLAY_TOKENS = {
    "SlenderMainMenu",
    "HauntedSlenderMainMenu",
    "WelcomeScreen",
    "Transition",
    "EmptyServerStart",
    "_Lighting",
    "_Blockout",
}

Config.LOADING_IMAGES = {
    forest = Config.MOD_ROOT_DIR .. "\\assets\\loading\\loading_slender_forest.png",
    house  = Config.MOD_ROOT_DIR .. "\\assets\\loading\\loading_slender_house.png",
    sketch = Config.MOD_ROOT_DIR .. "\\assets\\loading\\loading_slender_sketch.png",
}

Config.LOADING_SCREENS = {
    DEFAULT_MODE_TAG = "РЕЖИМ: ИГРА ЗА СЛЕНДЕРМЕНА",
    DEFAULT_SIZE_TAG = "1 ИГРОК ПРОТИВ АВТОНОМНОГО ИИ",
    DEFAULT_SUBTITLE = "ЦЕЛЬ: ВЫСЛЕДИТЬ И СЛОМИТЬ ВЫЖИВШЕГО",
    DEFAULT_TITLE    = "ИГРА ЗА СЛЕНДЕРМЕНА",
    DEFAULT_DESC     = "Возьмите под контроль самого Слендермена. Нагнетайте ужас [E], вызывайте панику [F] и пресекайте поиски жертвы [Q].",
    GENERIC_TIPS     = {
        "ИГРА ЗА СЛЕНДЕРМЕНА: Телепортация [Q] работает быстрее, когда человек не смотрит в выбранную точку.",
        "ИГРА ЗА СЛЕНДЕРМЕНА: Удерживайте [E] (Ужас), чтобы страх жертвы рос быстрее на средней дистанции.",
        "ИГРА ЗА СЛЕНДЕРМЕНА: Активное устрашение [F] вблизи вызывает внезапную панику и сбивает осмотр целей.",
        "ИГРА ЗА СЛЕНДЕРМЕНА: Доведите страх выжившего до критического уровня на 4 секунды, чтобы сломить его.",
        "ИГРА ЗА СЛЕНДЕРМЕНА: Следите за состоянием цели на панели [Tab] и отрезайте ей пути телепортом [Q].",
        "ИГРА ЗА СЛЕНДЕРМЕНА: Нажмите [F3] для свободной камеры или [F8] для быстрого перезапуска главы.",
    },
}

Config.MAPS = {
    PROLOGUE = {
        key           = "PROLOGUE",
        token         = "Level01_Prologue",
        path          = "/Game/Maps/Slender/Level01_Prologue",
        title         = "Prologue (House)",
        iconPath      = "/Game/Art/Slender/LevelIcons/revealed/levelicon_prologue.levelicon_prologue",
        loadingKey    = "house",
        loadingTitle  = "ПРОЛОГ — ДОМ КЕЙТ",
        loadingDesc   = "Выслеживайте Лорен внутри дома и во дворе. Открывайте дистанцию телепортом [Q] и ломайте её рассудок.",
        spawnDistMin  = 2400.0,
        spawnDistMax  = 3600.0,
        escapeMinDist = 2400.0,
    },
    EIGHT_PAGES = {
        key           = "EIGHT_PAGES",
        token         = "Level02_TheEightPages",
        path          = "/Game/Maps/Slender/Level02_TheEightPages",
        title         = "The Eight Pages",
        iconPath      = "/Game/Art/Slender/LevelIcons/revealed/levelicon_eightpages.levelicon_eightpages",
        loadingKey    = "forest",
        loadingTitle  = "ВОСЕМЬ ЗАПИСОК — ОКВУД",
        loadingDesc   = "Ночной лес принадлежит вам. Не дайте жертве собрать 8 записок: появляйтесь вне взгляда [Q] и вызывайте панику [F].",
        spawnDistMin  = 3500.0,
        spawnDistMax  = 5000.0,
        escapeMinDist = 2800.0,
    },
}

Config.CHAPTERS = {
    Config.MAPS.PROLOGUE,
    {
        key           = "PROLOGUE_YARD",
        token         = "Level01_HouseAndYard",
        path          = "/Game/Maps/Slender/Level01_HouseAndYard",
        title         = "House & Yard",
        iconPath      = "/Game/Art/Slender/LevelIcons/revealed/levelicon_prologue.levelicon_prologue",
        loadingKey    = "house",
        loadingTitle  = "ПРОЛОГ — ДОМ И ДВОР",
        loadingDesc   = "Тьма сгущается вокруг усадьбы. Подкрадитесь со спины [Q] и загоните выжившую в ловушку паники.",
        spawnDistMin  = 2400.0,
        spawnDistMax  = 3600.0,
        escapeMinDist = 2400.0,
    },
    Config.MAPS.EIGHT_PAGES,
    {
        key           = "INTO_THE_ABYSS",
        token         = "Level03_IntoTheAbyss",
        path          = "/Game/Maps/Slender/Level03_IntoTheAbyss",
        title         = "Into the Abyss",
        iconPath      = "/Game/Art/Slender/LevelIcons/revealed/levelicon_abyss.levelicon_abyss",
        loadingKey    = "forest",
        loadingTitle  = "В БЕЗДНУ — ШАХТА",
        loadingDesc   = "Глубины горной выработки полны узких коридоров. Отрезайте пути к генераторам [Q] и наводите ужас [F].",
        spawnDistMin  = 2200.0,
        spawnDistMax  = 3800.0,
        escapeMinDist = 2400.0,
    },
    {
        key           = "FLASHBACK",
        token         = "Level04_Flashback",
        path          = "/Game/Maps/Slender/Level04_Flashback",
        title         = "Flashback",
        iconPath      = "/Game/Art/Slender/LevelIcons/revealed/levelicon_flashback.levelicon_flashback",
        loadingKey    = "forest",
        loadingTitle  = "ВОСПОМИНАНИЕ — ДОЛИНА",
        loadingDesc   = "Преследуйте выжившего на пути через долину к башне. Перекрывайте маршруты и усиливайте давление [E].",
        spawnDistMin  = 3000.0,
        spawnDistMax  = 4600.0,
        escapeMinDist = 2600.0,
    },
    {
        key           = "THE_ARRIVAL",
        token         = "Level05_TheArrival",
        path          = "/Game/Maps/Slender/Level05_TheArrival",
        title         = "The Arrival",
        iconPath      = "/Game/Art/Slender/LevelIcons/revealed/levelicon_arrival.levelicon_arrival",
        loadingKey    = "sketch",
        loadingTitle  = "ПРИБЫТИЕ — ОБГОРЕЛЫЙ ЛЕС",
        loadingDesc   = "Среди дыма и обрывов охота становится смертельной. Удерживайте жертву в поле страха [E/F].",
        spawnDistMin  = 2800.0,
        spawnDistMax  = 4400.0,
        escapeMinDist = 2500.0,
    },
    {
        key           = "ESCAPE",
        token         = "Level06_Escape",
        path          = "/Game/Maps/Slender/Level06_Escape",
        title         = "Escape",
        iconPath      = "/Game/Art/Slender/LevelIcons/revealed/levelicon_escape.levelicon_escape",
        loadingKey    = "house",
        loadingTitle  = "ПОБЕГ — ДОМ",
        loadingDesc   = "Внутри запертого дома каждый коридор опасен. Не дайте цели вырваться на свободу.",
        spawnDistMin  = 1800.0,
        spawnDistMax  = 3200.0,
        escapeMinDist = 2200.0,
    },
    {
        key           = "MEMORIES",
        token         = "Level07_Memories",
        path          = "/Game/Maps/Slender/Level07_Memories",
        title         = "Memories",
        iconPath      = "/Game/Art/Slender/LevelIcons/revealed/levelicon_memories.levelicon_memories",
        loadingKey    = "sketch",
        loadingTitle  = "ВОСПОМИНАНИЯ — ПЛЯЖ И ЛЕС",
        loadingDesc   = "Прошлое возвращается кошмаром. Наблюдайте из темноты и сближайтесь в нужный момент [Q].",
        spawnDistMin  = 2400.0,
        spawnDistMax  = 4000.0,
        escapeMinDist = 2400.0,
    },
    {
        key           = "HOMESTEAD",
        token         = "Level08_Homestead",
        path          = "/Game/Maps/Slender/Level08_Homestead",
        title         = "Homestead",
        iconPath      = "/Game/Art/Slender/LevelIcons/revealed/levelicon_homestead.levelicon_homestead",
        loadingKey    = "house",
        loadingTitle  = "УСАДЬБА — ФЕРМА",
        loadingDesc   = "Тёмные амбары, часовня и поля скрывают цель. Сокращайте дистанцию телепортом [Q] и ломайте её психику [F].",
        spawnDistMin  = 2800.0,
        spawnDistMax  = 4400.0,
        escapeMinDist = 2500.0,
    },
    {
        key           = "GENESIS",
        token         = "Level09_Genesis",
        path          = "/Game/Maps/Slender/Level09_Genesis",
        title         = "Genesis",
        iconPath      = "/Game/Art/Slender/LevelIcons/revealed/levelicon_genesis.levelicon_genesis",
        loadingKey    = "forest",
        loadingTitle  = "ГЕНЕЗИС — ВОСЕМЬ ЗАПИСОК",
        loadingDesc   = "Классический ночной лес и восемь записок. Вы — безликий преследователь в тумане.",
        spawnDistMin  = 3500.0,
        spawnDistMax  = 5000.0,
        escapeMinDist = 2800.0,
    },
    {
        key           = "NIGHTMARE",
        token         = "Level10",
        path          = "/Game/Maps/Slender/Level10",
        title         = "Nightmare",
        iconPath      = "/Game/Art/Slender/LevelIcons/revealed/levelicon_nightmare.levelicon_nightmare",
        loadingKey    = "sketch",
        loadingTitle  = "КОШМАР — ДЕСЯТАЯ ГЛАВА",
        loadingDesc   = "Самая глубокая бездна ужаса. Настигните жертву до того, как она раскроет тайну.",
        spawnDistMin  = 2400.0,
        spawnDistMax  = 4000.0,
        escapeMinDist = 2400.0,
    },
    {
        key           = "HAUNTED",
        token         = "Level99_Haunted",
        path          = "/Game/Maps/Slender/Level99_Haunted",
        title         = "Haunted",
        iconPath      = "/Game/Art/Slender/LevelIcons/revealed/levelicon_nightmare.levelicon_nightmare",
        loadingKey    = "sketch",
        loadingTitle  = "ОДЕРЖИМОСТЬ",
        loadingDesc   = "Потусторонняя реальность под вашим контролем. Ужас [E] и Паника [F] решат исход охоты.",
        spawnDistMin  = 2400.0,
        spawnDistMax  = 4000.0,
        escapeMinDist = 2400.0,
    },
}

local function ExtractMapName(worldFullName)
    local s = tostring(worldFullName or "")
    -- Strip UE object class prefix ("World ") and package path
    local tail = s:match("%.([^%.]+)$") or s:match("([^/\\]+)$") or s
    return tail
end

function Config.IsMenuMap(worldFullName)
    local s = tostring(worldFullName or "")
    return string.find(s, "SlenderMainMenu", 1, true) ~= nil
end

function Config.IsExcludedNonGameplayMap(worldFullName)
    local s = tostring(worldFullName or "")
    if s == "" then return true end
    for _, bad in ipairs(Config.NON_GAMEPLAY_TOKENS) do
        if string.find(s, bad, 1, true) then
            return true
        end
    end
    return false
end

function Config.FindChapterByToken(str)
    local s = tostring(str or "")
    if s == "" then return nil end
    -- Prefer longest token match so e.g. Level01_HouseAndYard beats Level01
    local best, bestLen = nil, 0
    for _, cfg in ipairs(Config.CHAPTERS) do
        if string.find(s, cfg.token, 1, true) and #cfg.token > bestLen then
            best = cfg
            bestLen = #cfg.token
        end
    end
    return best
end

function Config.FindMapConfig(worldFullName)
    return Config.ResolveAnyPlayableMap(worldFullName)
end

function Config.ResolveAnyPlayableMap(worldFullName)
    if Config.IsExcludedNonGameplayMap(worldFullName) then
        return nil
    end
    local matched = Config.FindChapterByToken(worldFullName)
    if matched then
        return matched
    end
    local mapName = ExtractMapName(worldFullName)
    if mapName == "" then return nil end
    local cleanTitle = mapName:gsub("^Level%d+_", ""):gsub("_", " ")
    if cleanTitle == "" then cleanTitle = mapName end
    return {
        key           = string.upper(mapName:gsub("[^%w]+", "_")),
        token         = mapName,
        path          = "/Game/Maps/Slender/" .. mapName,
        title         = cleanTitle,
        iconPath      = Config.UI_ASSETS.TEX_ICON_EIGHT_PAGES,
        loadingKey    = "sketch",
        loadingTitle  = string.upper(cleanTitle) .. " — СЛЕНДЕРМЕН",
        loadingDesc   = Config.LOADING_SCREENS.DEFAULT_DESC,
        spawnDistMin  = 2600.0,
        spawnDistMax  = 4200.0,
        escapeMinDist = 2500.0,
        isCustom      = true,
    }
end

-- Asset Paths (verified in Stage A & Phase 1 Level01 probe)
Config.ASSETS = {
    SLENDER_CLASS      = "/Game/Blueprints/AI/Classes/Teleporter/BP_SlenderMan_Forest.BP_SlenderMan_Forest_C",
    SLENDER_MESH       = "/Game/Art/Characters/Slender/Slenderman/SK_Slender01.SK_Slender01",
    SLENDER_ANIM_BP    = "/Game/Art/Characters/Slender/Animations/ABP_Slender.ABP_Slender_C",
    SLENDER_IDLE_ANIM  = "/Game/Art/Characters/Slender/Animations/Thriller_Idle_Modified.Thriller_Idle_Modified",
    SLENDER_WALK_ANIM  = "/Game/Art/Characters/Slender/Animations/Sad_Walk.Sad_Walk",
    HUMAN_SHADOW_MESH  = "/Game/Art/Characters/Slender/CharliesParents/sk_laurenshadow.sk_laurenshadow",
    SOUND_DRAMATIC     = "/Game/Audio/AI/Teleporter/Dramatic/Teleporter_Dramatic.Teleporter_Dramatic",
    SOUND_MED_SIGHT    = "/Game/Audio/AI/Teleporter/Medium/Teleporter_Medium_Sight.Teleporter_Medium_Sight",
    SOUND_FAR_SIGHT    = "/Game/Audio/AI/Teleporter/Far/Teleporter_Far_Sight.Teleporter_Far_Sight",
}

-- Verified Native UI, Vignette, Camcorder, Audio & Tentacle Assets (Phase 1 Probe)
Config.UI_ASSETS = {
    -- Fonts & Verified Typeface Names
    FONT_HORROR            = "/Game/Art/UI/dbehavior_Font.dbehavior_Font",
    FONT_HORROR_TYPEFACE   = "Default",
    FONT_CAMCORDER         = "/Game/Art/UI/Fonts/pixelated_Font.pixelated_Font",
    FONT_CAMCORDER_TF      = "Default",
    FONT_BODY              = "/Game/Art/UI/Fonts/Jura/Jura.Jura",
    FONT_BODY_TF           = "Medium",
    FONT_BODY_BOLD_TF      = "Bold",

    -- Textures (UTexture2D)
    TEX_SLENDER_TITLE      = "/Game/Art/Slender/UI/ui_SlenderTitle.ui_SlenderTitle",
    TEX_BUTTON             = "/Game/Art/Slender/UI/button.button",
    TEX_BUTTON_ALT         = "/Game/Art/Slender/UI/pl_ui_slenderbutton1.pl_ui_slenderbutton1",
    TEX_HOVERER            = "/Game/Art/Slender/UI/hoverer.hoverer",
    TEX_SLIDER_BG          = "/Game/Art/Slender/UI/Volume/volumeslider.volumeslider",
    TEX_SLIDER_FILL        = "/Game/Art/Slender/UI/Volume/volumesliderfill.volumesliderfill",
    TEX_TENDRIL_1          = "/Game/Art/Slender/UI/Backdrop/tentacle1.tentacle1",
    TEX_TENDRIL_2          = "/Game/Art/Slender/UI/Backdrop/tentacle2.tentacle2",
    TEX_TENDRIL_3          = "/Game/Art/Slender/UI/Backdrop/tentacle3.tentacle3",
    TEX_SKETCH_SLENDER     = "/Game/Art/Slender/UI/Backdrop/sketch_0008.sketch_0008",
    TEX_SKETCH_ALT         = "/Game/Art/Slender/UI/Backdrop/sketch_0001.sketch_0001",
    TEX_SKETCH_DREAD       = "/Game/Art/Slender/UI/Backdrop/tentacle2.tentacle2",
    TEX_SKETCH_TERRIFY     = "/Game/Art/Slender/UI/Backdrop/sketch_0003.sketch_0003",
    TEX_ICON_PROLOGUE      = "/Game/Art/Slender/LevelIcons/revealed/levelicon_prologue.levelicon_prologue",
    TEX_ICON_EIGHT_PAGES   = "/Game/Art/Slender/LevelIcons/revealed/levelicon_eightpages.levelicon_eightpages",
    TEX_ICON_PAGE          = "/Game/Art/Slender/Textures/Pages/T_Page_A_C.T_Page_A_C",
    TEX_ICON_SPINNER       = "/Game/Art/Slender/Textures/loadingspinner1.loadingspinner1",
    TEX_CAMERA_FRAME       = "/Game/Art/UI/CameraHUD/ui_cameraFrame.ui_cameraFrame",
    TEX_REC_BADGE          = "/Game/Import/Intro/Textures/Camera/recording.recording_Texture",
    TEX_REC_DOT            = "/Game/Import/Intro/Textures/Camera/recsymb.recsymb_Texture",
    TEX_FADE_RECT          = "/Game/Art/UI/Textures/pl_ui_fade_rect.pl_ui_fade_rect",
    TEX_SCANLINES          = "/Game/Art/UI/Patterns/pl_ui_pat_scanlines001.pl_ui_pat_scanlines001",
    TEX_SCREEN_NOISE       = "/Game/Art/UI/Patterns/pl_ui_screenNoise.pl_ui_screenNoise",
    TEX_RADIAL_GRADIENT    = "/Game/Art/UI/radial_gradient.radial_gradient",
    TEX_CROSSHATCH         = "/Game/Art/UI/crosshatch.crosshatch",
    KEYCAP_PREFIX          = "/Game/Art/UI/ButtonSets/PC/black_",

    -- Verified UserInterface Materials (MaterialDomain = 5 / MD_UI)
    MAT_CHAPTER_SELECT     = "/Game/Art/Slender/UI/M_ChapterSelect.M_ChapterSelect",
    MAT_GAME_COMPLETE_BG   = "/Game/Art/Slender/UI/M_GameCompleteBackground.M_GameCompleteBackground",
    MAT_TEXT_HIGHLIGHT     = "/Game/Art/Slender/UI/M_UI_TextHighlightNew.M_UI_TextHighlightNew",
    MAT_SLENDER_BTN        = "/Game/Art/Slender/UI/MI_UI_SlenderButton1.MI_UI_SlenderButton1",
    MAT_SLENDER_BTN_HOVER  = "/Game/Art/Slender/UI/MI_UI_Slender_Button1_Hovered.MI_UI_Slender_Button1_Hovered",
    MAT_VIGNETTE           = "/Game/Art/UI/Materials/Backgrounds/MI_UI_background_vignette.MI_UI_background_vignette",
    MAT_BACKDROP_FADE      = "/Game/Art/UI/Materials/Backgrounds/MI_UI_BackdropFade.MI_UI_BackdropFade",
    MAT_SUBTITLE_LINE      = "/Game/Art/UI/Lines/Styles/MI_UI_Line_SubTitleLine.MI_UI_Line_SubTitleLine",
    MAT_BUTTON_FLARE       = "/Game/Art/UI/Menus/Buttons/MI_UI_Button_flare_Play.MI_UI_Button_flare_Play",

    -- Native Audio Cues
    SOUND_TENTACLES        = "/Game/Audio/NonPlayer/Slender/Tentacles/tentacles_Cue.tentacles_Cue",
    SOUND_STATIC_GLITCH    = "/Game/Audio/Camera/Glitch/staticglitch.staticglitch",
    SOUND_UI_CLICK         = "/Game/Audio/UI/click_Cue.click_Cue",
    SOUND_PAGE_GRAB        = "/Game/Audio/Pages/pagegrab_Cue.pagegrab_Cue",

    -- 3D Tentacles (from BP_Teleporter_C / BP_SlenderMan_Forest_C)
    TENTACLE_MESHES = {
        "/Game/Art/Slender/StaticMeshes/SM_Tentacle_01.SM_Tentacle_01",
        "/Game/Art/Slender/StaticMeshes/SM_Tentacle_02.SM_Tentacle_02",
        "/Game/Art/Slender/StaticMeshes/SM_Tentacle_03.SM_Tentacle_03",
        "/Game/Art/Slender/StaticMeshes/SM_Tentacle_04.SM_Tentacle_04",
    },
    TENTACLE_MATERIAL      = "/Game/Art/Environment/Props/Slender/Materials/MI_TentacleSkin.MI_TentacleSkin",
    TENTACLE_GROUP_LOC     = { X = -8.0, Y = -22.0, Z = 136.0 },
    TENTACLE_GROUP_ROT     = { Pitch = 8.0, Yaw = 90.0, Roll = 0.0 },
    TENTACLE_GROUP_SCALE   = { X = 0.56, Y = 0.56, Z = 0.56 },
}

-- Keybinds (UE Key FNames)
Config.KEYS = {
    FORWARD            = "W",
    BACKWARD           = "S",
    LEFT               = "A",
    RIGHT              = "D",
    SPRINT             = "LeftShift",
    TELEPORT           = "Q",
    PSYCHIC_DREAD      = "E",
    TERRIFY            = "F",
    TOGGLE_HAMMER      = "R",
    HAMMER_SWING       = "LeftMouseButton",
    HAMMER_HEAVY       = "RightMouseButton",
    TOGGLE_DEBUG       = "Tab",
    TOGGLE_DEBUG2      = "F1",
    TOGGLE_FREECAM     = "F3",
    TOGGLE_VISION      = "V",
    RESTART_ROUND      = "F8",
    QUICK_START        = "F9",
    QUICK_START_HOUSE  = "F9",
    QUICK_START_FOREST = "F7",
    FREECAM_UP         = "SpaceBar",
    FREECAM_DOWN       = "LeftControl",
}

-- Slenderman Movement & Physics (UE units: cm, cm/s)
Config.SLENDER = {
    WALK_SPEED        = 350.0,
    SPRINT_SPEED      = 600.0,
    CAPSULE_RADIUS    = 42.0,
    CAPSULE_HALF_HEIGHT = 115.0,
    MAX_STEP_HEIGHT   = 65.0,
    ROTATE_INTERP     = 10.0,
    SPAWN_DIST_MIN    = 3500.0, -- ~35-50 m from human start on open forest
    SPAWN_DIST_MAX    = 5000.0,
    CAPTURE_RADIUS    = 260.0,  -- Capture distance when human is heavily panicked
}

-- Camera Settings (Third-Person over-shoulder / rear orbit)
Config.CAMERA = {
    DISTANCE          = 340.0,
    HEIGHT_OFFSET     = 225.0,
    SHOULDER_OFFSET   = 45.0,
    MIN_DISTANCE      = 95.0,
    WALL_PADDING      = 28.0,
    MOUSE_SENS_YAW    = 0.16,
    MOUSE_SENS_PITCH  = 0.14,
    PITCH_MIN         = -55.0,
    PITCH_MAX         = 55.0,
    SMOOTH_POS_SPEED     = 16.0,
    TELEPORT_BLEND_SPEED = 8.0,
    FREECAM_SPEED        = 900.0,
    FREECAM_FAST_MULT    = 2.5,

    NIGHT_VISION_ENABLED        = true,
    NIGHT_VISION_RADIUS         = 3800.0,
    NIGHT_VISION_INTENSITY      = 0.75,
    NIGHT_VISION_FALLOFF_EXP    = 1.25,
    NIGHT_VISION_SOURCE_RADIUS  = 160.0,
    NIGHT_VISION_SPECULAR_SCALE = 0.03,
    NIGHT_VISION_COLOR          = { R = 0.80, G = 0.88, B = 1.0, A = 1.0 },
    NIGHT_VISION_EXPOSURE_BIAS  = 0.0,
    NIGHT_VISION_MIN_BRIGHTNESS = -1.2,
    NIGHT_VISION_GAMMA          = 1.0,
    NIGHT_VISION_VIGNETTE       = 0.05,
}

-- Slenderman Abilities
Config.ABILITIES = {
    TELEPORT_MIN_DIST     = 350.0,
    TELEPORT_MAX_DIST     = 3500.0,
    TELEPORT_COOLDOWN     = 6.0,
    TELEPORT_LOS_BLOCK_DIST = 1200.0, -- Cannot teleport right in front of human's central FOV

    DREAD_COOLDOWN        = 10.0,
    DREAD_DURATION        = 4.5,
    DREAD_RANGE           = 2800.0,
    DREAD_FEAR_PER_SEC    = 10.5,

    TERRIFY_COOLDOWN      = 14.0,
    TERRIFY_RANGE         = 1550.0,
    TERRIFY_PROXIMITY_NO_LOS = 650.0,
    TERRIFY_FEAR_MIN      = 22.0,
    TERRIFY_FEAR_MAX      = 32.0,
}

Config.HAMMER = {
    REACH_CM              = 460.0,
    MAX_SLENDER_REACH_CM  = 640.0,
    SWING_COOLDOWN        = 0.48,
    HEAVY_COOLDOWN        = 1.65,
    SWING_DURATION        = 0.34,
    HEAVY_DURATION        = 0.54,
    SWING_HIT_PHASE       = 0.42,
    HEAVY_HIT_PHASE       = 0.48,
    HEAVY_RADIUS_CM       = 340.0,
    MAX_ACTIVE_DEBRIS     = 90,
    SMALL_PROP_MAX_EXT    = 145.0,
    MEDIUM_PROP_MAX_EXT   = 420.0,
    GIANT_MESH_MIN_EXT    = 720.0,
    WALL_CRACKS_TO_BREAK  = 2,
    LIGHT_IMPULSE         = 950.0,
    HEAVY_IMPULSE         = 1650.0,
    HEAVY_RADIAL_IMPULSE  = 1150.0,
    CHUNKS_LIGHT_MIN      = 6,
    CHUNKS_LIGHT_MAX      = 9,
    CHUNKS_HEAVY_MIN      = 12,
    CHUNKS_HEAVY_MAX      = 18,
    SURVIVOR_HIT_FEAR     = 26.0,
    SURVIVOR_HEAVY_FEAR   = 38.0,
    SHAKE_LIGHT_CM        = 7.0,
    SHAKE_HEAVY_CM        = 18.0,
    SHAKE_DURATION        = 0.24,
}

-- Human AI, Perception, Fear & Navigation
Config.HUMAN = {
    FOV_HALF_ANGLE_DEG    = 58.0, -- 116 deg total horizontal FOV
    SLENDER_VISION_RANGE  = 4500.0,
    PAGE_VISION_RANGE     = 1750.0,
    SIXTH_SENSE_RADIUS    = 360.0,
    INTERACT_DISTANCE     = 260.0,
    INTERACT_DURATION     = 0.65,
    START_OBJECTIVE_GRACE_SEC = 5.0,

    WALK_SPEED            = 350.0,
    CAUTIOUS_SPEED        = 390.0,
    SPRINT_SPEED          = 590.0,
    PANIC_SPEED           = 620.0,
    BREAKDOWN_SPEED       = 210.0,

    STAMINA_MAX           = 100.0,
    STAMINA_DRAIN_RUN     = 10.0,
    STAMINA_DRAIN_PANIC   = 7.5,
    STAMINA_RECOVER_WALK  = 8.0,
    STAMINA_RECOVER_REST  = 18.0,

    FEAR_DECAY_DELAY      = 3.5,
    FEAR_DECAY_RATE       = 5.2,
    FEAR_RECOVER_RATE     = 9.0,
    FEAR_CRITICAL_TIME    = 4.0,   -- Must stay >= 98 under pressure (< 1600 cm) to break down
    FEAR_PRESSURE_RANGE   = 1600.0,

    NAV_REPLAN_INTERVAL   = 0.8,
    STUCK_CHECK_INTERVAL  = 1.5,
    STUCK_MIN_MOVE        = 85.0,
}

-- Update Rates (seconds)
Config.RATES = {
    PERCEPTION_HZ = 10.0,
    FEAR_HZ       = 10.0,
    FSM_HZ        = 4.0,
    UI_HZ         = 10.0,
}

Config.DEBUG = {
    SHOW_PANEL_ON_START = false,
    VERBOSE_LOG         = true,
}

function Config.LoadUserKeybinds()
    local candidates = {
        "ue4ss\\Mods\\PlayAsSlender\\keybinds.ini",
        "Mods\\PlayAsSlender\\keybinds.ini",
        "keybinds.ini",
    }
    for _, path in ipairs(candidates) do
        local f = io.open(path, "r")
        if f then
            local applied = 0
            for line in f:lines() do
                local clean = line:gsub("^%s+", ""):gsub("%s+$", "")
                if clean ~= "" and clean:sub(1, 1) ~= "#" and clean:sub(1, 1) ~= ";" and clean:sub(1, 1) ~= "[" then
                    local k, v = clean:match("^([%w_]+)%s*=%s*([%w_]+)$")
                    if k and v and Config.KEYS[k] ~= nil then
                        Config.KEYS[k] = v
                        applied = applied + 1
                    end
                end
            end
            f:close()
            return path, applied
        end
    end
    return nil, 0
end

Config.LoadUserKeybinds()

return Config
