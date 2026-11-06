# M1 MacBook Air Microphone Fix

Restore the built-in microphone on an **M1 MacBook Air (2020, J313)** running Omarchy / Arch Linux ARM with a compatible Aurora kernel.

On affected systems the Secure Enclave driver does not load automatically. The built-in microphone produces a brief startup transient followed by silence, even though a USB microphone works. Loading `apple-sep` with the read-only options below restored live microphone input and dictation on the tested Mac.

## Install

Once this repository has been published under `RobbieUK1/m1-macbook-air-microphone-fix`, run:

```bash
curl -fsSL https://raw.githubusercontent.com/RobbieUK1/m1-macbook-air-microphone-fix/main/install.sh -o /tmp/m1-microphone-install.sh && bash /tmp/m1-microphone-install.sh
```

The installer asks for administrator authentication. It starts the driver immediately and enables the same startup step for future boots. Select **MacBook Microphone** in your recording or dictation app; reopen the app if necessary. No reboot is normally needed to activate the fix.

To review the installer first, download it, read it, then run `bash install.sh`.

## What it changes

Installs and enables one systemd service:

```text
/etc/systemd/system/omarchy-m1-microphone.service
```

The service waits for the iBoot System Container device, then runs:

```bash
modprobe apple-sep xart_writes=0 provision_keybag=0
```

These options disable writes to the shared xART anti-replay store and disable Linux keybag provisioning. This does not enable Touch ID. The driver can create Linux-local host state in `/var/lib/aurora-sep-host-state.bin`.

The installer refuses other Mac models, incompatible drivers, and systems whose owner has enabled Touch ID through `/etc/omarchy-mac/touchid-on`. It does not change microphone volumes, audio routing, kernels, firmware, or package repositories. Running it again updates the same service. It also recognizes the earlier local version of this service used during diagnosis.

## Compatibility and checks

Tested on an M1 MacBook Air J313 running:

- Arch Linux ARM / Omarchy
- `linux-aurora 7.2.11.aurora14-1` (`7.2.11-14-1-ARCH`)
- PipeWire 1.6.9 and WirePlumber 0.5.18

This is a workaround for an affected Linux driver startup path, not a macOS fix or a repair for every microphone fault. A newer distribution package may provide its own equivalent startup service.

Check compatibility without making changes:

```bash
bash install.sh --check
```

Check the installed service:

```bash
systemctl status omarchy-m1-microphone.service
```

`active (exited)` is expected: it is a startup task, not a background process. Confirm the microphone by recording or dictating. Installation success alone does not verify live audio.

If the service fails, inspect:

```bash
journalctl -u omarchy-m1-microphone.service -b
journalctl -k -b | grep -i apple_sep
```

An already loaded driver keeps its existing options; this installer does not unload or reconfigure a running Secure Enclave driver. If you manually loaded it with different options, resolve that configuration before using this workaround.

## Uninstall

From a downloaded copy:

```bash
bash install.sh --uninstall
```

This removes only this workaround's service and its startup link. It leaves the currently loaded driver and any Linux-local state alone. Reboot when convenient for the removal to affect driver startup. A newer distribution fix may still load the driver independently.

## Background and credit

The cause and read-only startup approach are documented upstream:

- [Aurora kernel issue #141: J313 microphone returns a repeating pattern](https://github.com/omacom/linux-aurora/issues/141)
- [Upstream startup fix by Naeem Malik](https://github.com/omacom/omarchy-mac-pkgs/commit/7510ab66d4b12e2c80c5e93bf7956ea6ae6f9a74)

This repository packages that approach as a small standalone installer. It does not include a replacement driver.

## License

MIT. See [LICENSE](LICENSE).
