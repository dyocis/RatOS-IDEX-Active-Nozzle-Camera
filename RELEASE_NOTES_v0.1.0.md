# RatOS IDEX Active Nozzle Camera v0.1.0

## Initial Release

This is the first public release of **RatOS IDEX Active Nozzle Camera**.

### Highlights

- Automatically switches a single Mainsail **Active Nozzle** feed between T0 and T1.
- Follows the actual active RatOS IDEX toolhead.
- Supports nozzle cameras connected directly to the RatRig/RatOS Pi.
- Supports nozzle cameras hosted on a separate Raspberry Pi or Linux camera host.
- Leaves existing individual camera streams unchanged.
- Provides manual `/select`, `/status`, `/health`, stream, and snapshot endpoints.
- Includes install, uninstall, and verification scripts.
- Does not automatically restart Klipper.
- Avoids modifying RatOS stock `_SELECT_TOOL` macros.

### Validation

The release was validated on a RatRig V-Core 4 IDEX running RatOS 2.1 with dual nozzle cameras, Mainsail, and a separate Raspberry Pi camera host.

Validation included:

- manual T0/T1 camera switching
- remote switching from the RatOS printer Pi
- successful Klipper configuration load after restart
- manual RatOS T0/T1 tool selection
- a real two-color IDEX print

During the two-color print, the Active Nozzle feed switched correctly on every tool change.

### License

GNU General Public License v3.0 (GPL-3.0).
