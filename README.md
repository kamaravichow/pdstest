# Haven Smart Home (pdstest)

Flutter smart-home dashboard for Linux kiosk / desktop use.

## Install (Linux)

```bash
curl https://raw.githubusercontent.com/kamaravichow/pdstest/main/install.sh | bash
```

This downloads the latest release, installs the app, and by default enables XDG autostart plus display-manager autologin (kiosk mode).

### Options

| Variable | Default | Description |
| --- | --- | --- |
| `VERSION` | `latest` | Install a specific release tag (e.g. `v1.0.0`) |
| `PREFIX` | user install | System-wide install path (e.g. `/usr/local`; needs sudo) |
| `AUTOSTART` | `1` | Set `0` to skip auto-launch on login |
| `INSTALL_DEPS` | `1` | Set `0` to skip camera runtime deps: GStreamer (USB webcams) and, on Raspberry Pi, rpicam-apps (CSI camera modules) |
| `KIOSK` | `1` | Set `0` to skip display-manager autologin |
| `KIOSK_USER` | current user | Autologin as a specific user (e.g. `pi`) |

Examples:

```bash
# Specific version
curl -fsSL https://raw.githubusercontent.com/kamaravichow/pdstest/main/install.sh | VERSION=v1.0.0 bash

# System-wide
curl -fsSL https://raw.githubusercontent.com/kamaravichow/pdstest/main/install.sh | PREFIX=/usr/local bash

# Skip kiosk autologin
curl -fsSL https://raw.githubusercontent.com/kamaravichow/pdstest/main/install.sh | KIOSK=0 bash
```

If kiosk setup needs a sudo password, download first so the prompt works:

```bash
curl -fsSL https://raw.githubusercontent.com/kamaravichow/pdstest/main/install.sh -o /tmp/pdstest-install.sh
bash /tmp/pdstest-install.sh
```

## Development

```bash
flutter pub get
flutter run -d linux
```
