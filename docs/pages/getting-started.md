---
title: Getting Started
---

# Getting Started

Swihomo is a native mihomo client for iOS and macOS. It runs the mihomo core inside a system VPN tunnel, so you can use your own configuration or subscription without a separate helper app.

This guide takes you from installing the app to confirming that traffic is flowing. Each step points to more detail when you need it.

## Step 1: Install Swihomo

Swihomo requires iOS 17 or later, or macOS 14 or later. It is currently available through TestFlight; an App Store release is not yet available.

[Join the TestFlight beta](https://testflight.apple.com/join/ayecJQT4)

Accept the TestFlight invitation, install the build, and open Swihomo.

## Step 2: Add a profile

A profile holds the configuration the core runs. Open **Profiles** and choose one of these:

- **Online subscription**: select **Network Source**, paste an HTTP or HTTPS subscription URL, and select **Add Profile**. A **Profile Name** and **Custom User-Agent** are optional; the name defaults to the subscription host.
- **Local configuration**: open the **More** menu and select **Import**, then choose a YAML file. Swihomo uses the file name as the profile name.
- **QR code (iOS only)**: open the **More** menu, select **Scan QR Code**, and point the camera at a QR code that contains a subscription URL. The scan only fills in the URL; review the details, then select **Add Profile**.

The profile appears as a card on **Profiles**. Online cards offer **Refresh**; local cards do not.

For supported formats, validation, and editing, see [Profiles & Subscriptions](/profiles).

## Step 3: Connect

Select **Connect** on the profile card, or use the switch on **Home**. The first connection triggers the system prompt asking whether Swihomo may add a VPN configuration. Allow it to continue.

The button reads **Connected** once the tunnel is up. If you connect to a different profile while the tunnel is running, Swihomo switches to it automatically: it disconnects and reconnects with the new configuration. You do not need to disconnect first.

## Step 4: Confirm the connection

Open **Home**. The status card should read **Connected**, with the active profile name underneath.

Two more screens help you confirm that traffic is really flowing:

- **Connections** lists live connections with their matched rules and speeds. It shows content only while the tunnel is connected.
- **Logs** records app and mihomo core events. Core entries arrive while connected.

If something does not behave as expected, see [Status & Troubleshooting](/troubleshooting).

## Next steps

- [Profiles & Subscriptions](/profiles): subscription formats, refreshes, overrides, and deletion.
- [Settings](/settings): appearance, Packet Tunnel options, Overrides, and iCloud Sync.
