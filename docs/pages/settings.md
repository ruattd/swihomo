---
title: Settings
---

# Settings

Swihomo keeps device preferences on **Preferences**, shared runtime options on **Overrides**, and cross-device synchronization on **iCloud Sync** under **Tools**. This page covers the options most people change and explains when each change takes effect. [Getting Started](/getting-started) covers installation and your first connection.

## Preferences

**Preferences** contains per-device options. Appearance, Application, and Menu Bar preferences apply immediately; Packet Tunnel options apply after the tunnel reconnects.

### Appearance

Choose **Light**, **Dark**, or **System** to control the app's color scheme. **System** follows the device.

### Menu Bar

This section is available on macOS only.

- **Show Swihomo in the menu bar** adds a menu bar item with quick access to the app.
- **Display** chooses what the item shows: **Icon Only**, **Speed Only**, or **Icon + Speed**. **Icon Only** shows live transfer speeds in the menu instead of total traffic.
- **Hide Dock icon** removes the app from the Dock. It is available only after **Show Swihomo in the menu bar** is enabled.

### Application

- **App Log Level** sets the verbosity of Swihomo's own log entries: **Debug**, **Info**, **Warning**, or **Error**. It does not affect the mihomo core; set **Mihomo Log Level** on [Overrides](#overrides) for core logging.
- **Language** offers **System Default**, English, and 简体中文.
- **Auto-collapse other proxy groups** collapses other expanded proxy groups when you expand one.
- **Show Subscription Info** controls the usage row on subscription cards: **Hidden**, **Used**, or **Remaining**.

### Packet Tunnel

Every option in this section is read when the tunnel starts, so changes apply after you reconnect. The page states this directly: all settings below apply after you reconnect.

- **MTU** must be between 1280 and 4064; the default is 1500. An incorrect MTU can cause connection or network problems.
- **Route IPv6 through tunnel** is on by default. When it is off, IPv6 traffic may bypass mihomo.
- **Network Stack** chooses between gVisor and mipstack; mipstack is the default and uses less memory.
- **Congestion Controller** appears only when **Network Stack** is mipstack. Choose **Cubic**, **Reno**, **BBR**, or **BBRv3**. BBR usually performs better on high-latency or lossy links.
- **Custom DNS Servers** accepts one IPv4 or IPv6 resolver per line. These servers apply independently of the DNS settings in [Overrides](#overrides).
- **Include all networks** is off by default. When enabled, it adds three bypass switches: **Bypass cellular services**, **Bypass local networks**, and **Bypass APNs**.
- **Bypass IP Ranges** accepts one IPv4 or IPv6 CIDR range per line, such as `192.168.1.0/24` or `2001:db8::/32`.

### Experimental

- **Automatically reclaim memory** asks mihomo to release unused memory under critical memory pressure. It applies the next time you connect, and may increase garbage collection and battery use.
- **Replace Geo databases with rulesets** rewrites `GEOIP` and `GEOSITE` rules and DNS geosite policies to mrs rulesets and removes geo database settings. It applies the next time you connect. `dns.fallback-filter.geosite` is not migrated. See [Geo databases and memory](/troubleshooting#geo-databases-and-memory) for when this matters.
- **Realtime delay test** uses per-node delay testing instead of the group API. It affects the Proxies page immediately.
- **Delay test concurrency** sets how many delay tests run at once, from 1 to 32; the default is 4. It is available only while **Realtime delay test** is on.

## Overrides

**Overrides** holds global runtime settings shared by every profile. They are independent of any subscription, so a refresh never removes them.

### Basic Settings

Basic settings are applied after your custom YAML, so they always take priority over values in a profile or custom override.

- **Routing Mode**: **Rule**, **Global**, or **Direct**; the default is **Rule**.
- **Mihomo Log Level**: **Debug**, **Info**, **Warning**, **Error**, or **Silent**. Silent produces no core log entries.
- **Allow LAN connections** and **Enable IPv6** are off by default.
- **Enable DNS** is on by default.
- **Mixed Port** accepts a value from 1 to 65535; the default is 7890.

Routing mode, core log level, **Mixed Port**, **Allow LAN connections**, and **Enable IPv6** take effect on the running core immediately.

### External Controller

- **Enable external controller** exposes the mihomo REST API on `127.0.0.1` for third-party clients. The app talks to the core directly, so it keeps working when the controller is off.
- **Controller Port** defaults to 9090 and accepts a value from 1 to 65535.
- **Controller secret** is generated randomly on first run and can be shown or hidden. The port and secret fields are disabled until the controller is enabled.

### Custom YAML Override

The custom YAML editor deep-merges fields into each profile at connect time without modifying the source subscription. It uses the same Mihomo Party override syntax as profile overrides:

- `key!` replaces the existing object.
- `+key` or `key+` prepends or appends array items.
- `<key>` escapes a literal plus-prefixed or plus-suffixed key.

The in-app link opens the [Mihomo Party YAML override reference](https://clashparty.org/docs/guide/override/yaml).

### Saving and reconnecting

The footer shows **All changes saved** or **Unsaved changes**, and explains the timing: basic settings update live, while DNS, external controller, and YAML changes apply after reconnect.

If you save changes that need a reconnect while connected, Swihomo asks **Reconnect to Apply Changes?** with **Reconnect** and **Not Now**. Declining is safe; the saved changes wait until the next connection.

### Relationship with profiles

Global **Basic Settings** apply to every profile. The global custom YAML also applies to every profile unless you turn off **Enable Global Overrides** on that profile's [override sheet](/profiles#profile-overrides). Profile overrides are merged after the global custom YAML and before the standard overrides.

## iCloud Sync

Open **Tools**, then **iCloud Sync**, to keep settings and profiles consistent across your devices. The master switch controls syncing; a category syncs only while its switch is on, and turning a switch off never removes data already in iCloud.

**Sync Status** shows the latest event and when it happened, or **No sync activity yet.** Use **Sync Now** to sync on demand.

The categories cover:

- **Preferences**: general preferences, sorting, Packet Tunnel configuration, and Experimental configuration.
- **Profiles**: the profile list with contents, subscription URLs, and per-profile custom overrides, plus **Global Overrides**.

Two pieces of data stay on the device and are not synced: the active profile selection, and the external controller secret. Profile content syncs verbatim, including any secret present in a subscription or override YAML.

**Danger Zone** offers **Delete iCloud Data**, which removes what Swihomo stored in iCloud without affecting data on this device.

If iCloud already contains synced settings when you first enable sync, Swihomo asks whether to use the iCloud settings or keep the local ones.

## Which changes need a reconnect

| Change | When it applies |
| --- | --- |
| Appearance, Application, Menu Bar preferences | Immediately |
| Packet Tunnel options | After reconnect |
| Routing mode, core log level, Mixed Port, Allow LAN, Enable IPv6 | Immediately |
| Enable DNS, external controller, controller port or secret, custom YAML | After reconnect |
| Geo-to-ruleset replacement, automatic memory reclaim | On the next connection |
| Profile overrides | On the next connection of that profile |

Selecting a different profile while connected reconnects automatically, so its settings load without a separate manual reconnect.

## See also

- [Profiles & Subscriptions](/profiles): importing, refreshing, and overriding profiles.
- [Status & Troubleshooting](/troubleshooting): status states, logs, resources, and memory limits.
