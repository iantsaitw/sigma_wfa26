# Sigma Tool Control Script

**Note: The testing environment is automatically initialized upon reboot. Please wait about 60 seconds after booting, then run `sigma status` to verify the environment before starting your tests.**

## Usage
`sigma [command]`

## Commands
* `boot`    : Reloads the rtw89 driver, compiles the tool, and starts WFA services.
* `start`   : Compiles the tool and starts WFA services (skips driver reload).
* `stop`    : Terminates active WFA processes (wfa_dut, wfa_ca, wpa_supplicant).
* `restart` : Performs a complete reset (`stop` -> `boot`).

## Monitoring & Troubleshooting
* Run `sigma status` to check the driver, WFA components, and ports.
* If you notice any anomalies or connection issues, simply run `sigma restart` to restore a clean environment.
