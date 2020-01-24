-- mello
--
-- enc 1 = fade between sample 0 - 1
-- enc 2 = pitch +/- sample 0
-- enc 3 = pitch +/- sample 1
--
-- key 2 = fade 100% sample 0
-- key 3 = fade 100% sample 1
-- key 2+3 = 50/50%




-- VARIABLES
local Timber = include("timber/lib/timber_engine")

engine.name = "Timber"

local g = grid.connect(1)

local SCREEN_FRAMERATE = 15
local screen_dirty = true

local NUM_SAMPLES = 2
local voice_ids = {}
local strings = {} -- table of playback rates built by halfsteps on 'strings'

local detune_param = "detune_cents_"
local transpose_param = "transpose_"
local amp_param = "amp_"
local play_mode_param = "play_mode_"

local fade = 0
local fade_width = 100
local amp_0 = 0
local amp_1 = 0
local amp_range_0 = (-48) - amp_0
local amp_range_1 = (-48) - amp_1



-- SETUP FUNCTIONS
local function make_ids()
  -- make two unique ids for each grid key
  local i = 0
  for y=1, g.rows do
    voice_ids[y] = {}
    for x=1, g.cols do
      voice_ids[y][x] = i
      i = i + 2
    end
  end
end

local function note(steps, f)
  -- equally spaced scale with 12 steps,
  -- where steps is n steps from frequency f.
  return ((2 ^ (1/12)) ^ steps) * f
end

local function retune()
  for y=8,2,-1 do
    strings[y] = {}
    for x=1,16 do
      strings[y][x]=note((x-1), note((8-y) * params:get("tuning_interval"), params:get("tuning_freq")))
    end
  end
end

local function adjust_fade()
  if fade > 0 then
    engine.amp(0, (amp_range_0/100) * math.abs(fade))
    engine.amp(1, (amp_1))
  elseif fade < 0 then
    engine.amp(0, (amp_0))
    engine.amp(1, (amp_range_1/100) * math.abs(fade))
  else
    engine.amp(0, (amp_0))
    engine.amp(1, (amp_1))
  end
end

local function set_pitch_bend_voice(voice_id, bend_st)
  engine.pitchBendVoice(voice_id, MusicUtil.interval_to_ratio(bend_st))
end

local function set_pitch_bend_sample(sample_id, bend_st)
  engine.pitchBendSample(sample_id, MusicUtil.interval_to_ratio(bend_st))
end

local function set_pitch_bend_all(bend_st)
  engine.pitchBendAll(MusicUtil.interval_to_ratio(bend_st))
end



-- DISPLAYS
local function redraw()
  local st_0 = params:get(transpose_param..0)
  local c_0 = params:get(detune_param..0)
  local st_1 = params:get(transpose_param..1)
  local c_1 = params:get(detune_param..1)
  
  if st_0 >= 0 then
    st_0 = "+"..st_0
  end
  
  if st_1 >= 0 then
    st_1 = "+"..st_1
  end
  
  if c_0 >= 0 then
    c_0 = "+"..c_0
  end
  
  if c_1 >= 0 then
    c_1 = "+"..c_1
  end
  
  screen.clear()
  
  screen.level(15)
  
  screen.move(10, 32)
  screen.text("L")
  screen.move(118, 32)
  screen.text_right("R")
  
  screen.move(63,42)
  screen.text_center("FADE")
  
  screen.move(18,32)
  screen.line_width(1)
  screen.line(110,32)
  screen.stroke()
  
  -- fade marker on panner
  screen.move((100/110/2) * fade + 64,28)
  screen.line_rel(0,7)
  screen.stroke()
  
  screen.level(4)
  
  screen.move(18, 24)
  screen.text("sample 0")
  screen.move(110, 24)
  screen.text_right("sample 1")
  
  screen.move(26,49)
  screen.text_center(st_0)
  screen.move(26,57)
  screen.text_center("st")
  screen.move(42,49)
  screen.text_center(c_0)
  screen.move(42,57)
  screen.text_center("c")
  
  screen.move(102,49)
  screen.text_center(st_1)
  screen.move(102,57)
  screen.text_center("st")
  screen.move(86,49)
  screen.text_center(c_1)
  screen.move(86,57)
  screen.text_center("c")
 
  screen.update()
end



-- INIT
function init()
  make_ids()
  
  -- Callbacks
  Timber.sample_changed_callback = function(id)
    
    if Timber.samples_meta[id].manual_load then
      
      -- Set our own loop point defaults
      params:set("loop_start_frame_" .. id, util.round(Timber.samples_meta[id].num_frames * 0.2))
      params:set("loop_end_frame_" .. id, util.round(Timber.samples_meta[id].num_frames * 0.5))
      
      -- Set env defaults
      params:set("amp_env_attack_" .. id, 0.01)
      params:set("amp_env_sustain_" .. id, 0.8)
      params:set("amp_env_release_" .. id, 0.4)
    end
    
  end
  
  -- Add params
  params:add{
    type = "number",
    id = "bend_range",
    name = "Pitch Bend Range",
    min = 1,
    max = 48,
    default = 2,
  }
  
  params:add{type = "number",
    id = "tuning_interval",
    name = "String Interval",
    min = 1,
    max = 12,
    default = 5,
    action = function(value) retune() end
  }
  
  params:add{type = "number",
    id = "tuning_freq",
    name = "Bottom String Freq",
    min = 20,
    max = 480,
    default = 440,
    action = function(value) retune() end
  }
  
  params:add_separator()
  
  Timber.add_params()
  for i = 0, NUM_SAMPLES - 1 do
    params:add_separator()
    Timber.add_sample_params(i)
  end
  
  -- overwrite default set-action for amp control
  -- (-48db) is min of parameter
  params:set_action(amp_param..0, 
    function(value)
      amp_0 = value
      amp_range_0 = (-48) - amp_0
      adjust_fade()
      Timber.views_changed_callback(0)
    end
  )
  params:set_action(amp_param..1, 
    function(value)
      amp_1 = value
      amp_range_1 = (-48) - amp_1
      adjust_fade()
      Timber.views_changed_callback(1)
    end
  )
  
  Timber.load_sample(0, _path.audio .. "/tehn/whirl1.aif")
  Timber.load_sample(1, _path.audio .. "/tehn/whirl2.aif")
  
  -- UI
  local screen_refresh_metro = metro.init()
  screen_refresh_metro.event = function()
    if screen_dirty then
      redraw()
      screen_dirty = false
    end
  end
  screen_refresh_metro:start(1 / SCREEN_FRAMERATE)
  
  retune()
  redraw()
end



-- CONTROLS
function key(n, z)
  if z == 1 then
    if n == 1 then
      
    elseif n == 2 then
      if key_down then
        fade = 0
      else
        fade = -fade_width
      end
      key_down = true
      adjust_fade()
    elseif n == 3 then
      if key_down then
        fade = 0
      else
        fade = fade_width
      end
      key_down = true
      adjust_fade()
    end
  elseif z == 0 then
    key_down = false
  end
  screen_dirty = true
end

function enc(n, delta)
  if n == 1 then
    -- turn left = -vol sample 1, turn right = -vol sample 0
    fade = util.clamp((fade + delta), -fade_width, fade_width)
    adjust_fade()
  else
    -- continuous detune by cents, +/- 48 semitones
    if delta > 0 then
      if params:get(detune_param..(n-2)) == 100 then
        params:set(detune_param..(n-2), 0)
        params:delta(transpose_param..(n-2), 1)
      else
        params:delta(detune_param..(n-2), delta)
      end
    else
      if params:get(detune_param..(n-2)) == -100 then
        params:set(detune_param..(n-2), 0)
        params:delta(transpose_param..(n-2), -1)
      else
        params:delta(detune_param..(n-2), delta)
      end
    end
  end
  screen_dirty = true
end

function g.key(x, y, z)
  if z == 1 then
    if y == 1 then
      -- pitch bend
      return
    end
    engine.noteOn(voice_ids[y][x], strings[y][x], 1, 0)
    engine.noteOn(voice_ids[y][x] + 1, strings[y][x], 1, 1)
    g:led(x,y,15)
    g:refresh()
  end
  
  if z == 0 then
    engine.noteOff(voice_ids[y][x])
    engine.noteOff(voice_ids[y][x] + 1)
    g:led(x,y,0)
    g:refresh()
  end
end
