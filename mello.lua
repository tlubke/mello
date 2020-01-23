-- mello
--
-- enc 1 = fade between sample 0 - 1
-- enc 2 = pitch +/- sample 0
-- enc 3 = pitch +/- sample 1

local Timber = include("timber/lib/timber_engine")
local MusicUtil = require "musicutil"
local UI = require "ui"
local Formatters = require "formatters"

engine.name = "Timber"

local g = grid.connect(1)

local SCREEN_FRAMERATE = 15
local screen_dirty = true

local NUM_SAMPLES = 2
local voice_ids = {}

local detune_param = "detune_cents_"
local transpose_param = "transpose_"
local amp_param = "amp_"
local play_mode_param = "play_mode_"

local strings = {} -- table of playback rates built by halfsteps on 'strings'
local tuning_a = 440

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

local function note(halfsteps,f)
  -- equally spaced 12-note chromatic
  return ((2 ^ (1/12)) ^ halfsteps) * f
end

local function retune()
  for y=8,2,-1 do
    strings[y] = {}
    if y>=5 then
      for x=0,15 do
        strings[y][x]=note(x, note((8-y) * 5, tuning_a))
      end
    else
      for x=0,15 do
        strings[y][x]=note(x, note((5 - y) * 7, strings[5][0]))
      end
    end
  end
end

local function note_on(voice_id, freq, vel, sample_id)
  engine.noteOn(voice_id, freq, vel, sample_id)
  screen_dirty = true
end

local function note_off(voice_id, sample_id)
  engine.noteOff(voice_id)
  screen_dirty = true
end

local function note_off_all()
  engine.noteOffAll()
  screen_dirty = true
end

local function note_kill_all()
  engine.noteKillAll()
  screen_dirty = true
end

local function set_pressure_voice(voice_id, pressure)
  engine.pressureVoice(voice_id, pressure)
end

local function set_pressure_sample(sample_id, pressure)
  engine.pressureSample(sample_id, pressure)
end

local function set_pressure_all(pressure)
  engine.pressureAll(pressure)
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

local function redraw()
  screen.clear()

  -- draw stuff

  screen.update()
end

local function grid_redraw()
  g:all(0)
  
  -- draw stuff
  
  g:refresh()
end

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
  params:add{type = "number", id = "bend_range", name = "Pitch Bend Range", min = 1, max = 48, default = 2}
  
  params:add_separator()
  
  Timber.add_params()
  for i = 0, NUM_SAMPLES - 1 do
    params:add_separator()
    Timber.add_sample_params(i)
  end
  
  -- equally spaced from -48db and 16db
  -- quick and dirty "fade" for now
  params:set(amp_param..0, -16)
  params:set(amp_param..1, -16)
  
  Timber.load_sample(0, _path.audio .. "/common/606/606-BD.wav")
  Timber.load_sample(1, _path.audio .. "/common/606/606-SD.wav")
  
  -- UI
  screen.aa(1)
  
  local screen_refresh_metro = metro.init()
  screen_refresh_metro.event = function()
    if screen_dirty then
      redraw()
      screen_dirty = false
    end
  end
  screen_refresh_metro:start(1 / SCREEN_FRAMERATE)
  
  retune()
  grid_redraw()
end

function g.key(x, y, z)
  if z == 1 then
    if y == 1 then
      -- pitch bend
      return
    end
    note_on(voice_ids[y][x], strings[y][x-1], 1, 0)
    note_on(voice_ids[y][x] + 1, strings[y][x-1], 1, 1)
    g:led(x,y,15)
    g:refresh()
  end
  
  if z == 0 then
    note_off(voice_ids[y][x], 0)
    note_off(voice_ids[y][x] + 1, 1)
    g:led(x,y,0)
    g:refresh()
  end
end

function enc(n, delta)
  if n == 1 then
    -- turn left (+ sample 0), turn right (+ sample 1)
    params:delta(amp_param..0, -delta)
    params:delta(amp_param..1, delta)
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
