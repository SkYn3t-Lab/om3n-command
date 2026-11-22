# Changelog

Each version's entry is its release notes. The newest is first, and `om3n-command.ps1 selftest` checks that it is
the version the app itself reports (`om3n-command.ps1 version`).

## 1.0.0 (2026-11-21)

The first release.

- A Setup that installs Om3n Command, or updates it, and adds it to the Start menu, the desktop and Settings > Apps,
  where Uninstall removes it and offers to delete your settings, logs and recorded readings as well.
- The app starts with Windows as an icon in the notification area and opens with no administrator prompt.
- Any HP OMEN desktop with an Intel processor and an AMD Radeon card: the app reads the processor, the graphics card
  and the limits each reports when it starts, and every range, scale and default comes from that PC.
- Voltages, speed limits and the graphics power limit are changed in exact steps within what the hardware allows,
  with Apply; an undervolt goes no further than 150 mV and moves at most 25 mV per change, and a voltage change puts
  the previous value back by itself unless it is kept within 15 seconds.
- Eleven pages: Home, Fans, Lighting, Processor, Graphics, Displays, Games, Sensors, Logging, Alerts and Activity.
- Case fans: Quiet, Balanced and Performance through the BIOS, and Om3n, which switches between them by processor
  temperature.
- Case and memory lighting through the lighting controller and the BIOS, and the graphics card's own light on
  RX 7900 XTX reference cards, with two built-in looks (Om3n, the default, and Dark, every light off), your own saved looks, effects, the sign-in screen and sleep.
- Processor top speed by busy cores, undervolt and power limit through Intel's tuning service, without Intel's library.
- Radeon features, power and clock limits, undervolt, the fan curve and 3D settings through AMD's driver interfaces,
  without AMD Software running.
- Each monitor's picture settings through the driver, and its own menu over DDC/CI, including HP's gaming settings on
  an OMEN monitor.
- Graphics settings of ARC Raiders (Steam, Epic and Xbox app copies) and Battlefield 6 (EA app and Steam copies) from each game's own file, with a tuned set, Apply and Revert.
- A recorder that keeps 14 days of readings, crash reports after an unclean shutdown, temperature alerts, and Hold my
  settings, which puts back what another program changed.
- Tested on AMD Software: Adrenalin Edition 26.11.2 (driver 32.0.32029.2010). Radeon Super Resolution is offered only while AMD
  Software is running.
