---
title: Status & Troubleshooting
---

# Status & Troubleshooting

Swihomo shows connection state on **Home** and exposes live traffic, logs, and provider files elsewhere in the app. This page explains what those screens report and lists checks that are safe to try before you change a configuration. It does not include a catalog of error messages, because failures usually depend on the profile and the network rather than on a fixed app message.

## Home status

The status card at the top of **Home** reports one of four states:

- **Connected**: the tunnel is up.
- **Connecting**: a connection is in progress.
- **Disconnecting**: a disconnect is in progress.
- **Not connected**: no tunnel is running.

The active profile name appears under the status; if no profile is active, the card asks you to choose one. The connect switch is disabled while there is no active profile or while a connection is changing state.

If the status looks wrong, first confirm the active profile on [Profiles](/profiles), then refresh the subscription or reconnect. If the status is **Connected** but traffic does not flow, use **Connections**, **Logs**, and **Resources** below.

## Connections

**Connections** shows live traffic only while the tunnel is connected. While disconnected, the page asks you to connect first.

- Each row shows the process, the destination, the matched rule, and current download and upload speeds. The list refreshes every second.
- The search field matches process name, destination, destination IP, remote destination, and `ip:port`.
- The sort menu orders rows by **Process**, **Live Speed**, or **Rule**, in ascending or descending direction.
- Open a row for **Connection Details**: live speed and traffic totals, the rule and rule payload, the proxy chain and provider chain, and protocol, source, host, destination, remote destination, and process path. Values the core does not report appear as **Not reported**.
- **Close All** closes every connection managed by mihomo after a confirmation. Use it if connections look stale after changing settings.

The proxy chain is the most direct answer to "why did this traffic go there?": it lists the rule that matched and the proxies that handled the connection.

## Logs

**Logs** combines two sources:

- **App** covers lifecycle, profile, tunnel, proxy, and error events from Swihomo itself.
- **Core** carries mihomo's own log stream. Core entries arrive only while the tunnel is connected.

Each source keeps its newest 1,000 entries on the device. The page reloads when you open it and polls while it is visible.

- Filter by source (**All**, **App**, **Core**) and by level (**All levels**, **Debug**, **Info**, **Warning**, **Error**).
- Search matches the module, the message, the source name, and the level name.
- **More** offers **Return to Bottom** and **Clear Logs**.

Two different settings raise log detail. **App Log Level** in [Preferences](/settings#preferences) controls app entries only. **Mihomo Log Level** in [Overrides](/settings#overrides) controls core entries; **Silent** stops core entries entirely. Set both to **Debug**, reproduce the problem, then filter or search for the relevant module.

Clearing logs is permanent. **Clear Logs** lets you remove **App Logs**, **Core Logs**, or **All**. If you clear core logs while disconnected, Swihomo performs that clear the next time the core starts.

When an operation fails, Swihomo shows an error banner with the reported description. The same error is also recorded as an app log entry, so you can dismiss the banner and read the full context in **Logs**.

## Resources

**Resources** lists the files mihomo needs for the active profile: **Proxy Providers**, **Rule Providers**, and **Geo Data**. The page works only while connected, and it discovers files from the providers that the merged configuration references.

Each card shows a status:

- **READY** means the file exists on disk. It is a presence check, not a validity check, so a corrupt file can still show **READY**.
- **MISSING** means the file is absent.
- Geo Data also shows whether it is **Cached in MihomoCore** or **Not cached yet**.

**Last updated** comes from the core, or from the app's own record for Geo Data. **Update** refreshes the enabled geodata databases for Geo Data cards, and loads or downloads the file for provider cards. For providers, after **Update** the provider contents are reloaded into the running core.

For provider files, **Edit** opens a UTF-8 text editor and **Replace** lets you choose a file. Geo Data can be replaced but not edited. Replacing a Geo database file requires a reconnect to load it; provider files load through **Update**.

If a required resource stays **MISSING**, select **Update** to download it, or **Replace** it with a file, then reconnect so the core loads it. **READY** only confirms that a file exists, so verify that its contents match the provider type the profile declares.

## Settings that need a reconnect

Some changes are read only when the tunnel starts:

- Every option under [Packet Tunnel](/settings#packet-tunnel).
- **Enable DNS**, the external controller, its port or secret, and the custom YAML override under [Overrides](/settings#overrides).
- **Replace Geo databases with rulesets** and **Automatically reclaim memory** under [Experimental](/settings#experimental), which state that they apply on the next connection.
- A profile's [custom overrides](/profiles#profile-overrides), which load the next time that profile connects.

To apply them, disconnect and connect again from **Home**, or save in **Overrides** and accept **Reconnect to Apply Changes?**. Switching to a different profile while connected also reconnects automatically.

## Geo databases and memory

On mobile devices, the system enforces a memory limit of roughly 50 to 70 MB for Network Extensions and terminates the extension when it is exceeded. Geo databases commonly consume 30 MB or more at startup and can grow further.

If the VPN disconnects unexpectedly or fails to start with a geo-heavy configuration, reduce that footprint:

- Enable **Replace Geo databases with rulesets** in [Experimental](/settings#experimental). Swihomo rewrites `GEOIP` and `GEOSITE` rules and DNS geosite policies to mrs rulesets and removes the database settings. `dns.fallback-filter.geosite` is not migrated, so review that policy if you use it.
- Select **mipstack** as the **Network Stack** in [Packet Tunnel](/settings#packet-tunnel); it uses less memory than gVisor.
- Enable **Automatically reclaim memory** to let mihomo release unused memory under pressure.

All three take effect on the next connection. The core log also records a critical memory pressure warning when automatic reclaim triggers.

## Safe checks

Work through these in order; each one uses a screen that reports real state rather than a guess.

1. Confirm on **Home** that the status is **Connected** and that the expected profile name is shown.
2. Reconnect after changing any setting listed above, or switch profiles to trigger a fresh connection.
3. Raise **App Log Level** and **Mihomo Log Level** to **Debug**, reproduce the problem, then filter by source and search for the module or message.
4. Open **Connections**, search for the affected destination, and inspect the matched rule and proxy chain.
5. Open **Resources** and confirm every required provider and Geo file is **READY**; update providers and check **Last updated**.
6. Read the error banner and the matching app log entry for the reported failure.
7. For repeated disconnects or failed starts with Geo databases, apply the memory reductions above and reconnect.

## See also

- [Profiles & Subscriptions](/profiles): adding, refreshing, and overriding profiles.
- [Settings](/settings): preferences, Overrides, and iCloud Sync.
