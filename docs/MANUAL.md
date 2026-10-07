# Om3n Command: the manual

Every command and option of Om3n Command. For what it is, what it needs and how to install it, see the
[README](../README.md). `om3n-command.ps1` is the command-line tool underneath the app; the commands below are
typed in PowerShell as administrator, in `C:\Program Files\Om3n Command\app`.

## Where everything is

```
C:\Program Files\Om3n Command\      the app; only an administrator can change it
  install.ps1  repair.ps1  uninstall.ps1
  Om3n Command.vbs  Om3n Command.cmd   what the shortcut runs, and the plain start
  README.md  LICENSE
  docs\       the manual
  app\        the tool (om3n-command.ps1), the window and everything they call
  tools\      checks and measurements you run by hand
  assets\     the icon
  defaults\   the lighting look a new install starts with

C:\ProgramData\SkYn3tLab\            yours; never replaced by an install
  om3n-command-lights.json            saved lighting looks
  om3n-command-startup.txt            the sign-in list
  om3n-command-*.json / .txt / .log   other settings, and the logs
  telemetry\                          recorded readings and crash reports
```

The download also holds the builders and source images of the icon, the artwork and the README's pictures (`assets\`), and
`examples\om3n-command-startup.txt`, one PC's sign-in list as an example. None of those is installed.

## Start it

**The app** is already running: it starts at sign-in as an icon in the notification area (by the clock). Click the
icon, or double-click the `Om3n Command` shortcut on the desktop, and the window opens, with no administrator
prompt. Closing the window leaves the app running in the notification area, where it keeps recording; right-click
the icon for the fan setting or **Quit**. The icon's tip shows the processor and graphics temperatures.

```powershell
.\om3n-command.ps1 app        # is it set to start at sign-in, is it running
.\om3n-command.ps1 app off    # stop starting it at sign-in ("app on" puts that back)
```

With `app off`, `Om3n Command.cmd` in `C:\Program Files\Om3n Command` still starts it, and asks Windows for administrator rights.
The window opens the size and place it was closed at (kept in
`C:\ProgramData\SkYn3tLab\om3n-command-window.json`); the first time, at 85% of the screen.

| Page | What you do there |
|---|---|
| Home | On the right, the settings changed most: the case fan setting, the processor undervolt, the graphics voltage, the graphics card's fan curve (drag a point; it is sent when you let go), the fan stop, your saved lighting looks and the settings in force (the same commands as their own pages; applied changes go into the sign-in list). On the left (above, in a narrow window), a live telemetry console, refreshed every second: one row per reading with its last three minutes as a chart, drawn as the Logging page draws its own (a scale at the left, a mark every 30 seconds, the warning value as a dashed line). Processor temperature, load and clock, power; graphics temperature, hotspot, memory temperature, load and clocks, power and fan, graphics memory; memory, network, drive activity. Below: the settings in force (fans, undervolt, top speed, power limit, drive temperature) and your saved lighting looks. Each line is green while its reading is in a reasonable range, amber from its warning value and red from its danger value; a reading with no limit (load, network, drive activity) is grey. The value itself turns amber, then red, the same way. The limits: temperatures as on the Alerts page, processor power 125 and 170 W, graphics power 355 and 400 W, memory 85 and 95 % full |
| Fans | Pick Quiet, Balanced, Performance or Om3n (`fan auto`, which switches between the three by processor temperature), and set the two temperatures Om3n uses (they are remembered) |
| Lighting | Press a saved look, or give each light a colour and an effect; save what you set as a new look. Below: brightness, direction and more colours per light; what each light shows while the PC sleeps; and the two live effects (colour by temperature or load, pulse with the sound), with Stop |
| Processor | A slider for the top speed at each number of busy cores, the voltage offset (undervolt), a switch that puts the offset back at every sign-in, and the memory speed for the next restart (it asks before sending; the BIOS retrains the memory at that restart) |
| Graphics | On/off switches for the Radeon features, sliders for sharpening, the frame rate limit and the power limit. Below: the clock and current limits (move a slider, then press Set; nothing is sent until you do), the 3D settings (V-Sync, anti-aliasing, anisotropic filtering, tessellation) and a button that clears the shader cache |
| Displays | Brightness, contrast, colour strength, tint and warmth for each monitor, plus scaling and HDR |
| Sensors | Every reading the PC offers without a driver of its own, live, one row each: its value now and the lowest, highest and average seen, with a button to start those again. The processor (temperature, load, clock, power), each processor thread's load and clock, the graphics card (temperatures, clocks, voltage, power, fan, memory, and the driver's other sensors under AMD's own names), memory, network and drive. Not there, because Windows offers them only through a kernel driver: a temperature per core, the motherboard's voltages, the case fans and the pump |
| Logging | What the recorder wrote down, as one line per reading over the last hour, 6 hours, 24 hours or 7 days, with lowest, average and highest; each line takes the colour of its highest value in the time shown (green, amber, red, or grey for a reading with no limit); unclean shutdowns marked in red; the hottest moment of each reading; the crash reports and graphics driver reset reports. Live: the charts are read again every 5 seconds for the last hour and every 30 seconds for the longer spans |
| Alerts | The temperature alerts: on or off for each reading, the two temperatures each alerts from, how long a reading must stay there and how long the app stays quiet afterwards |
| Activity | Every command the app has run and what came back |

Everything the app does is one `om3n-command.ps1` command, so anything below can also be typed. If something does not
work, the bar at the bottom says so and the Activity page has the details.

Only one window runs at a time: starting the app again brings the open one to the front. A command that has not
finished after 60 seconds is stopped and reported.

`om3n-command.ps1` ends with exit code 0 when the change was made, 2 when the PC refused it (out of range, not
supported), and 1 when the command itself failed. The app goes by that code, not by the wording of the output.
`om3n-command.ps1 state` prints everything the app's pages show (fan selection, processor controls, graphics sensors,
settings and features, the sign-in list) as one JSON document; `state cpu` and `state gpu` print one part. A part
that could not be read is named in its `errors` list.

**The command line:** open PowerShell as administrator in `C:\Program Files\Om3n Command\app`.

```powershell
.\om3n-command.ps1 status
```

If PowerShell refuses to run the script, start it as
`powershell -ExecutionPolicy Bypass -File .\om3n-command.ps1 status`.

## Files

As installed, by folder (see "Where everything is").

| File | What it is |
|---|---|
| `app\om3n-command.ps1` | The tool. Every command goes through it |
| `app\om3n-command-ui.ps1` | The app, Om3n Command |
| `app\om3n-command-dash.cs` | The Home page's live readings (the app compiles it when it starts) |
| `app\om3n-command-lib.ps1` | Shared by the app and the probes: loads the readings, reads the fan selection |
| `assets\om3n-command.ico` | The app's icon |
| `Om3n Command.vbs` | What the desktop shortcut runs: opens the app with no administrator prompt |
| `Om3n Command.cmd` | Starts the app the plain way, with the administrator prompt (used when `app off`) |
| `app\om3n-command-shortcut.ps1` | Puts the `Om3n Command` shortcut on your desktop (run once) |
| `app\om3n-command-page-more.ps1` | The extra controls on the Fans, Lighting, Processor and Graphics pages |
| `app\om3n-command-hid.ps1` | Sets the four case lighting zones by writing to the lighting controller directly (no HP software) |
| `app\om3n-command-hold.ps1` | Hold my settings: decides what to put back when OMEN Gaming Hub replaces a setting |
| `app\lights-at-boot.ps1` | Applies a saved lighting look when Windows starts, before sign-in (`on <look>`, `off`) |
| `tools\gpu-reset-dumps.ps1` | Opens the newest graphics driver reset dumps with the Windows debugger and prints what each says |
| `tools\dash-reopen-test.ps1` | Checks that the live readings reconnect to the graphics driver after it is closed and reopened |
| `app\om3n-command-history.ps1`, `app\om3n-command-page-history.ps1` | The Logging and Alerts pages and the temperature alerts |
| `app\om3n-command-page-sensors.ps1` | The Sensors page |
| `C:\ProgramData\SkYn3tLab\om3n-command-lights.json` | Lighting profiles (see below) |
| `C:\ProgramData\SkYn3tLab\om3n-command-startup.txt` | Commands run at every sign-in (see "At every sign-in") |
| `tools\undervolt-abtest.ps1` | Measures what the voltage offset does: the same load at 0, -100 and 0 mV, with power, temperature and clock (loads 4 cores for about 5 minutes) |
| `tools\gpu-sensor-sample.ps1` | Samples the graphics card's own sensors for a set time, with min / average / max |
| `tools\lag-probe.ps1` | Measures whether a read or a change stalls the whole PC (`-FanWrite` times the fan mode call, re-sending the mode in force) |
| `app\om3n-command-live.ps1` | Live readings for the fed lighting effects (vitals, audio) |
| `app\cpu-tune.ps1` | CPU tuning through Intel's tuning service |
| `app\radeon-read.ps1` | Radeon sensors and tuning settings |
| `app\radeon-set.ps1` | Sets one Radeon tuning setting |
| `app\radeon-features.ps1` | Anti-Lag, Boost, Image Sharpening, Chill, frame-rate target |
| `app\radeon-adlx.ps1` | Super Resolution, Fluid Motion Frames, 3D settings, VSR |
| `app\radeon-display.ps1` | Per-display settings |
| `app\om3n-command-blackbox.ps1` | The black box: what the app uses to record readings and write crash reports (see "Logs") |
| `app\run-interactive.ps1` | Runs a script in the desktop session when you are signed in remotely (the processor, graphics and display commands only work there) |
| `install.ps1`, `repair.ps1`, `uninstall.ps1` | See "Install, update, repair, uninstall" in the README |
| `app\om3n-command-check.ps1` | Reads every installed script with PowerShell's parser and prints each file's SHA256 |
| `tools\timing-probe.ps1` | Times how long the tool's commands take |

## Fans

The BIOS has exactly three fan modes and nothing finer. The fan selection is one of four:

```powershell
.\om3n-command.ps1 fan quiet
.\om3n-command.ps1 fan normal      # what Gaming Hub calls Balanced
.\om3n-command.ps1 fan turbo       # what Gaming Hub calls Performance
.\om3n-command.ps1 fan auto        # picks among the three from the CPU temperature
```

`fan auto` starts a hidden background process that checks the processor temperature every 5 seconds: Quiet below 50 C,
Turbo from 75 C, Normal in between, and it steps back down only 5 C below each threshold, and only once the
temperature has stayed there for 60 seconds (`-DownAfter`). Going up is immediate. The wait is there because every
fan mode change stops the whole PC for about a third of a second: the BIOS does that, and nothing in Windows can
shorten it (`tools\lag-probe.ps1 -FanWrite` measures it). Fewer changes is the only cure.
Change the thresholds with `-QuietBelow`, `-TurboAbove` and `-Hysteresis`:

```powershell
.\om3n-command.ps1 fan auto -QuietBelow 45 -TurboAbove 70
```

The automatic selection runs until you choose quiet, normal or turbo. Choosing it adds its line to the sign-in list,
so it starts again at every sign-in; choosing a fixed setting takes the line off. Its mode changes are logged to `C:\ProgramData\SkYn3tLab\om3n-command-auto.log`, and
`status` shows which selection is in force.

The BIOS cannot report the fan mode, so the tool remembers the last mode it set. If OMEN Gaming Hub sets a mode
afterwards, the tool does not see it.

## Lighting

Zones: `Logo`, `InternalBar`, `FrontFan`, `CpuFan` (the case) and `Ram`.

```powershell
.\om3n-command.ps1 light CpuFan 255 5 10                               # static colour: red green blue, 0-255
.\om3n-command.ps1 light FrontFan 255 10 255 -Effect breathing -Speed slow
.\om3n-command.ps1 light Logo -Effect cycle -Theme galaxy
.\om3n-command.ps1 light Logo -Effect wave -Theme omen
.\om3n-command.ps1 light CpuFan -Effect cycle -Colors '255,0,0;0,255,0;0,0,255'
.\om3n-command.ps1 light CpuFan -Effect off
.\om3n-command.ps1 light Ram 255 5 5 -Effect breathing -Brightness 50
```

| Option | Values |
|---|---|
| `-Effect` | `static` (default), `breathing`, `cycle`, `blinking`, `wave`, `spiral`, `vitals`, `audio`, `off` |
| `-Theme` | `galaxy`, `volcano`, `jungle`, `ocean` (built into the controller); `omen`, `unicorn`, `arcane`, `valorant`, `hyperx` (Gaming Hub's colour lists) |
| `-Speed` | `slow`, `medium`, `fast` |
| `-Brightness` | `0`, `25`, `50`, `75`, `100` |
| `-Direction` | `0` or `1`, for wave and spiral |
| `-Colors` | several colours for an animated effect: `'r,g,b;r,g,b;...'` |
| `-State sleep` | sets what a case zone shows while the PC sleeps |
| `-Simulate` | prints what would be sent and sends nothing |

The RAM has static, breathing, cycle, blinking, wave and off. Its colour cycle and its themed wave use built-in
colours, and it has no spiral.

Two effects follow something live and run for `-Seconds`, after which the zone keeps the last frame:

```powershell
.\om3n-command.ps1 light FrontFan -Effect vitals -Source cputemp -Preset 1 -Seconds 600
.\om3n-command.ps1 light FrontFan 255 5 10 -Effect audio -Band bass -Seconds 600
```

`-Source` is `cputemp`, `cpuload`, `gputemp` or `gpuload`. `-Band` is `level`, `bass` or `treble`.

OMEN Gaming Hub does not know about colours set here. While it is installed it re-sends its own stored colours
when you unlock the PC.

### Lighting profiles

A profile is a name and one line per zone, each line being what you would type after `light`. They live in
`C:\ProgramData\SkYn3tLab\om3n-command-lights.json`.

```powershell
.\om3n-command.ps1 lights              # list the profiles
.\om3n-command.ps1 lights Om3n        # apply one
```

**Om3n** is the look a new install starts with:

| Zone | Colour (red, green, blue) |
|---|---|
| Logo | 113, 15, 250 |
| InternalBar | 113, 15, 250 |
| FrontFan | 255, 10, 255 |
| CpuFan | 255, 5, 10 |
| Ram | 255, 5, 5 |

To add a profile, add a name and its lines to the file:

```json
{
  "Om3n": ["Logo 113 15 250", "InternalBar 113 15 250", "FrontFan 255 10 255", "CpuFan 255 5 10", "Ram 255 5 5"],
  "Night": ["Logo 20 0 40", "InternalBar 20 0 40", "FrontFan -Effect off", "CpuFan -Effect off", "Ram 20 0 40 -Brightness 25"]
}
```

## CPU tuning

Through Intel's tuning service (the same backend Gaming Hub uses), with no Intel library.

```powershell
.\om3n-command.ps1 cpu                              # every control: default, active, boot and proposed value, range
.\om3n-command.ps1 cpu -ControlId 0x61 -Value 47    # set one control
```

Max turbo ratio by active cores: `0x1D` (1 core), `0x1E`, `0x1F`, `0x20`, `0x2A`, `0x2B`, `0x60`, `0x61` (8 cores).
The service decides what it accepts. A change that would need a restart is discarded, not applied. After a set
the tool lists every control that changed.

### Undervolt

The voltage offset is control `0x22` (core) and `0x4F` (ring), in millivolts, 0 at factory. Setting the core offset
moves the ring offset with it:

```powershell
.\om3n-command.ps1 cpu -ControlId 0x22 -Value -90
```

Lower runs cooler; `tools\undervolt-abtest.ps1` measures by how much on your PC (the same load at 0, -100 and
0 mV, with power, temperature and clock). Too low makes the PC crash or freeze. The offset is not stored in the BIOS, so a restart always comes back at 0: a bad value cannot stop the PC
from starting.

Intel's service log may report `OcMailboxTuning reported DidNotAttempt` for a voltage write. That line does not
mean the offset was refused: the measurement above shows whether it applies.

### At every sign-in

Because a restart drops the offset (and any turbo ratio change), `startup` re-applies a list of commands one
minute after you sign in:

```powershell
.\om3n-command.ps1 startup         # is it on, what it runs, how the last run went
.\om3n-command.ps1 startup on      # register the sign-in task
.\om3n-command.ps1 startup off     # remove it
.\om3n-command.ps1 startup run     # run the list now
```

The list is `C:\ProgramData\SkYn3tLab\om3n-command-startup.txt`, one line per command, each being what you would type after `om3n-command.ps1`.
The voltage slider on the Processor page rewrites it, after a change that went through, while the sign-in switch
is on. Each run is logged to `C:\ProgramData\SkYn3tLab\om3n-command-startup.log`. If an undervolt ever makes the PC
unstable right after sign-in, you have one minute to run `startup off`.

Everything the app runs, and what came back, is also kept in `C:\ProgramData\SkYn3tLab\om3n-command-app.log`, so an
error can still be read after the app is closed.

Applying a processor voltage offset can move the processor's sustained power limit as a side effect. The tool lists every control an apply changed, so read that list; a `cpu -ControlId 0x30 -Value 125` line
after the offsets on the sign-in list holds the limit at 125 W.

### After a crash

If the PC went down without a clean shutdown (a freeze, a reset, a blue screen) since the last sign-in, an
undervolt is the first suspect. So at that sign-in the undervolt lines of the list (processor voltage, processor
cache voltage, graphics voltage) are held back once, everything else in the list still runs, and Home shows a
notice with two buttons: **Put it back now**, or **Take it off the sign-in list**. If you do nothing, the undervolt
returns at the next sign-in.

```powershell
.\om3n-command.ps1 startup run -Simulate                 # what the next sign-in would do, and why
.\om3n-command.ps1 startup run -Simulate -PretendCrash   # the same, as if the PC had just crashed
.\om3n-command.ps1 startup restore                       # put the held lines back now
.\om3n-command.ps1 startup drop                          # take them off the list
```

## Hold my settings

OMEN Gaming Hub sends its own fan setting when you unlock the PC and its own lighting when it starts and at unlock
(processor settings only from its own tuning page). With **Hold my settings** on (Home, bottom right; on by default), the app puts yours back: the fan setting
and the look you last applied 5 seconds after an unlock and a minute after the app starts, and the undervolt and
graphics lines of the sign-in list whenever a check every 5 minutes finds a different value in force. A setting is
put back at most once every 2 minutes, and after 3 times in 10 minutes the app stops and says so in its log
(`HOLD stopped for ...`) rather than pull back and forth. Undervolt lines held back after a crash are not put back.

A graphics driver reset (the screen freezes, goes black for a moment and the game closes) puts the card back to its
stock voltage and hands the fan back to the card. The app then holds a graphics voltage from the sign-in list back,
says so on Home, and returns it at the next sign-in; and it sends your fan curve again (also once each time the app
starts, since it cannot tell then who is running the fan). The live readings reconnect
to the card on their own. `tools\gpu-reset-dumps.ps1` prints what Windows recorded for the newest resets.
Each reset also gets a report, within one reading of it: `C:\ProgramData\SkYn3tLab\telemetry\reset-<time>.txt`
(the readings for three minutes before it, what was set, what was running; the newest ten
are listed on the Logging page), and a
`RESET` line in the app's log.
Fans on Om3n (`fan auto`) are left alone. Kept in `C:\ProgramData\SkYn3tLab\om3n-command-hold.json`.

## Temperature alerts

When the processor, the graphics hotspot, the graphics memory or the system drive stays at or over its limit for
30 seconds, the icon by the clock shows a notice and the app log gets a line. It does not repeat for 15 minutes
unless the reading reaches the stronger limit, and it re-arms once the reading is 5 C under the limit. Limits (first
/ stronger): processor 80 / 90 C, hotspot 100 / 105 C, graphics memory 90 / 100 C, drive 84 / 88 C (the drive's own
warning and critical temperatures). Change them, switch all alerts off, or switch one reading's alert off (the switch beside it), on the
Alerts page. The only other notice the app shows is "still running", once per run when you first close its window;
its switch is in the same place. Kept in
`C:\ProgramData\SkYn3tLab\om3n-command-alerts.json`.

## Radeon

```powershell
.\om3n-command.ps1 gpu                                         # sensors, tuning settings, feature states
.\om3n-command.ps1 gpu -Setting POWER_PERCENTAGE -Value 5      # one tuning setting; the driver's range is enforced
.\om3n-command.ps1 gpu -Setting FAN_CURVE_SPEED_3 -Reset       # back to the driver's default
.\om3n-command.ps1 gpu -Feature antilag -Enable 1
.\om3n-command.ps1 gpu -Feature sharpen -Enable 1 -Value 70
.\om3n-command.ps1 gpu -Feature framecap -Enable 1 -Value 144
.\om3n-command.ps1 gpu -Setting vsync -Value 3
.\om3n-command.ps1 gpu -Setting shadercache -Reset             # games rebuild their shaders on next launch
```

| Group | Names |
|---|---|
| Tuning (`-Setting`) | `POWER_PERCENTAGE`, `GFXCLK_FMAX`, `GFXCLK_FMIN`, `UCLK_FMAX`, `OD_VOLTAGE`, `TDC_PERCENTAGE`, `FAN_ZERORPM_CONTROL`, `FAN_CURVE_TEMPERATURE_1`..`5`, `FAN_CURVE_SPEED_1`..`5` |
| Features (`-Feature`) | `antilag`, `boost`, `sharpen`, `chill`, `framecap`, `rsr` (Radeon Super Resolution), `afmf` (Fluid Motion Frames) |
| 3D settings (`-Setting`) | `enhancedsync`, `vsync`, `aamode`, `aalevel`, `aamethod`, `maa`, `af`, `aflevel`, `tessmode`, `tesslevel` |

AMD Software may keep showing its own defaults after a tuning change made here.

**Graphics undervolt.** `OD_VOLTAGE` is the highest voltage the chip may use, 700-1150 mV, stock 1150. For example:

```powershell
.\om3n-command.ps1 gpu -Setting OD_VOLTAGE -Value 1100
.\om3n-command.ps1 gpu -Setting OD_VOLTAGE -Reset     # back to 1150
```

The Graphics page has the same as a slider (1000-1150 mV), and a change made there goes into the sign-in list.

**Graphics fan curve.** Five temperature / speed points, written together; the card follows its hotspot
temperature:

```powershell
.\om3n-command.ps1 gpu -FanCurve 30,23,50,38,67,53,85,68,95,100   # AMD's own curve
```

Writing a curve, even AMD's own, moves the fan from the card's automatic control onto the curve;
`.\om3n-command.ps1 gpu -FanCurve reset` hands it back. On Home the fan has three profiles: **Automatic** (the card
decides, as from the factory), **AMD** (AMD's curve, which ramps from 30 C and so is rarely silent) and **Om3n** (the tuned one, AMD's curve with its two faults removed: the lowest speed up to 60 C, so idle is quiet, then one even ramp to full speed at 95 C with no jump at the end). Dragging a point changes Om3n's curve; pressing Om3n puts its own back. A curve profile is put back at every
sign-in, since after a restart the card is on Automatic again.
Too low shows up as a game crash or the screen freezing for a moment. `tools\gpu-sensor-sample.ps1` samples the card's own
voltage, clock, temperatures and power for a set time (run it in the desktop session while a game runs) to judge it.

## Displays

```powershell
.\om3n-command.ps1 display                                              # every connected display and its settings
.\om3n-command.ps1 display -Display 0 -Set saturation -Value 160
.\om3n-command.ps1 display -Display 0 -Set vsr -Value 1
```

`-Set` is one of `brightness`, `contrast`, `saturation`, `hue`, `temperature`, `gpuscaling`, `hdr`, `colordepth`,
`pixelformat`, `vsr`, `freesync`, `integerscaling`. Setting `hdr`, `colordepth` or `pixelformat` blanks the
screen for a moment. Two monitors of the same model have the same name, so check which number is which before you change one.

## Sensors and memory

```powershell
.\om3n-command.ps1 status          # temperatures, load, fan selection
.\om3n-command.ps1 sensors         # everything Windows offers: CPU power, per-thread load and frequency, GPU, drives, network
.\om3n-command.ps1 memory          # memory profile in use
.\om3n-command.ps1 memory 3200     # select a profile for the NEXT boot (a BIOS setting; needs a restart)
```

## What this machine cannot do

- **Custom fan curves, per-fan speed, pump speed.** The BIOS offers three modes and has no command for anything else.
- **Chassis fan and pump readings.** Nothing reports them, HWiNFO included.
- **Per-core temperatures, voltages, the SATA drive's temperature.** They need a kernel driver, which this tool does not have.
- **Network Booster.** HP's service refuses the call from outside Gaming Hub.
- **LEDs on the graphics card.** Not supported.

## Logs

Everything is in `C:\ProgramData\SkYn3tLab\` (the Activity page has **Open the log folder**). Each line is written
straight through to the disk, so the last lines survive a freeze.

| File | What is in it |
|---|---|
| `telemetry\telemetry-<date>.csv` | The black box: one line a second while the app runs, every reading the Home graph draws (it runs from sign-in, window open or not). Processor temperature, load, clock, power; graphics temperature, hotspot, memory temperature, load, clocks, voltage, power, fan; memory; and which program was in front. Kept 14 days |
| `telemetry\crash-<time>.txt` | Written at the first start after the PC stopped without a clean shutdown: the blue-screen code (0 means a freeze, reset or power loss), the last three minutes of readings before it went down, the settings changed before it, the sign-in list, hardware-error records |
| `om3n-command-changes.log` | The settings journal: a `START` line before every change, then `END`, or `ERROR` if the command failed. A `START` with nothing after it means the PC went down during that change |
| `om3n-command-app.log` | The app: opened, closed, every command with its output, and every error with where it happened. An error in a control no longer closes the app; it is logged and shown on the status bar |
| `om3n-command-startup.log` | The last run of the sign-in list |
| `telemetry\blackbox-errors.log` | Why the recorder stopped, when it is run by hand outside the app (inside the app, errors go to `om3n-command-app.log`) |

```powershell
.\om3n-command.ps1 log            # is the black box recording, latest reading, crash reports
.\om3n-command.ps1 log show       # the last minute of readings
.\om3n-command.ps1 log crash      # the newest crash report
.\om3n-command.ps1 log changes    # the last 30 lines of the settings journal
.\om3n-command.ps1 log off        # stop recording ("log on" starts it again); the app obeys within seconds
```

The app in the notification area, recorder included, is one PowerShell process of about 170 MB (measured). If you
Quit the app, recording stops until it is started again.

## Stopping OMEN Gaming Hub, HP's services and AMD Software from starting

Neither app is needed for anything above, and both can write the same settings. The switch "OMEN Gaming Hub and AMD
Software start with Windows" on Home does this (off runs `off -CloseNow`, on runs `on`). Or, from an administrator PowerShell:

```powershell
.\vendor-startup.ps1                  # show what is set and what is running
.\vendor-startup.ps1 off -CloseNow    # turn their sign-in starts off and end the running copies
.\vendor-startup.ps1 on               # put every start back
```

`off` disables Gaming Hub's startup task, its background tasks (Microsoft's "Let Windows apps run in the
background" policy, force-deny for the Gaming Hub package: without it Windows still starts Gaming Hub's background
process at every sign-in, and it sends its own lighting and fan setting) and its `OmenInstallMonitor` and
`OmenOverlay` tasks, and AMD Software's
`StartCN` and `StartDVR` tasks, and sets HP's six background services to Disabled (`HPOmenCap`, `HPAppHelperCap`,
`HPDiagsCap`, `HPNetworkCap`, `HPSysInfoCap`, `HpTouchpointAnalyticsService`). Nothing is uninstalled and the AMD
driver's services stay. What you give up: OMEN Gaming Hub altogether until you run `on`, and AMD Software's overlay,
hotkeys, recording and update notices. AMD Software still opens by hand and starts its background part until you
sign out. A driver install or an app
update may turn the starts back on: run `off` again.

## Lighting before you sign in

```powershell
.\lights-at-boot.ps1                  # show whether it is on, and the last run
.\lights-at-boot.ps1 on Om3n         # apply that saved look every time Windows starts
.\lights-at-boot.ps1 off
```

The same choice is on the Lighting page ("At the sign-in screen"). A scheduled task applies the look as the system account when Windows starts, so the lights are set at the sign-in
screen. It runs the installed `om3n-command.ps1`, which only an administrator can change. Its log is `C:\ProgramData\SkYn3tLab\om3n-command-lights-boot.log`.
