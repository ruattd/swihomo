---
title: Profiles & Subscriptions
---

# Profiles & Subscriptions

A profile is the mihomo configuration Swihomo runs. Local YAML files and online subscriptions live side by side on the **Profiles** page, and you can switch between them at any time. Profiles are kept in the app's private storage, so you manage them from the app rather than from the file system.

## The Profiles page

Each profile is a card that shows where its configuration came from:

- **Local** means an imported YAML file. Its detail line reads **Imported configuration**.
- **Online** means a subscription. Its detail line shows the subscription host.
- The active card is marked **ACTIVE** and supplies the configuration used when you connect.

Cards also show **Updated** with the last time the stored configuration changed, or **Updated —** when the date is unknown. Online cards show **Subscription** usage and **Expires** when the subscription server reports them; the usage row is hidden when **Show Subscription Info** is set to **Hidden** in [Preferences](/settings#preferences).

## Import a local profile

1. Open **Profiles**.
2. Open the **More** menu and select **Import**.
3. Choose a UTF-8 YAML configuration file.

Swihomo imports one file at a time and names the profile after the file, without its extension. Local profiles have no rename action and no **Refresh** button; use **Edit Content** to change them. Empty files are rejected.

## Add an online subscription

1. Open **Profiles** and select **Network Source**.
2. Enter the subscription details:

   - **Subscription URL** is required and must be an HTTP or HTTPS URL with a host. Swihomo validates it as you type.
   - **Profile Name** is optional. It defaults to the subscription host and only identifies the profile inside Swihomo.
   - **Custom User-Agent** is optional. It is used for the first download and every later refresh, and defaults to `ClashMeta/<mihomo-version>`. Leave it empty to keep the default.

3. Select **Add Profile**. The button stays disabled until the URL is valid.

The download has a 30 second timeout, and an HTTP error is reported as a failure. Swihomo accepts mihomo YAML configurations, JSON subscription lists, common share-link lists, and base64-encoded subscriptions. A JSON list of proxy nodes is wrapped into a profile with a `Proxy` group and a `MATCH` rule.

## Add a subscription from a QR code

On iOS, select **Scan QR Code** from the **More** menu on **Profiles**, then point the camera at a QR code that contains an HTTP or HTTPS subscription URL. A valid code opens the **Add Online Profile** sheet with the URL already filled in; nothing is imported until you review the sheet and select **Add Profile**. If the code does not contain a usable URL, the scanner reports that it is not a subscription URL.

## Connect and switch profiles

Select **Connect** on a card to start the tunnel. While that profile is active and connected, its button reads **Connected**.

Selecting **Connect** on another card while the tunnel is running switches to it automatically. Swihomo disconnects, then reconnects with the newly selected profile. The first connection also shows the system prompt for VPN configuration permission. [Settings](/settings) explains which changes need a reconnect.

## Keep a subscription up to date

Online profiles have two editing paths, and they do different things:

- **Refresh** downloads the subscription again with the stored URL and User-Agent. It replaces the stored content and updates the **Updated** date and subscription usage. Refresh is manual; there is no scheduled or automatic refresh.
- **Edit Profile** changes the subscription URL, the **Profile Name**, or the **Custom User-Agent**. This is the only way to rename an online profile. It does not download anything until you refresh.

**Edit Content** is available for every profile and opens a YAML editor. Saving updates the **Updated** date. For an online profile the edit is local: the subscription URL is unchanged, and the next **Refresh** overwrites whatever you saved. Use [profile overrides](#profile-overrides) for changes that should survive a refresh.

## Profile overrides

Open a card's **More** menu and select **Overrides...** to customize one profile. The sheet is titled **Profile Custom Override** and applies on top of the global custom YAML, before the app's standard overrides.

- **Enable Global Overrides** decides whether this profile also applies the custom YAML from the global [Overrides](/settings#overrides) page. It is on by default.
- The YAML editor accepts the same Mihomo Party syntax as the global editor.

When the profile connects, Swihomo merges in this order:

1. The profile's own configuration.
2. Global custom YAML, if **Enable Global Overrides** is on.
3. This profile's custom YAML.
4. Standard overrides generated from the global basic settings, which always win.
5. An optional rewrite that replaces Geo database references with rulesets.

Saved override changes take effect the next time the profile connects.

## Delete a profile

Open the card's **More** menu and select **Delete Profile**. The confirmation states that the profile and its stored configuration are removed and that the action cannot be undone. If you delete the active profile, the active selection is cleared; choose another profile before connecting again.

## See also

- [Settings](/settings): Packet Tunnel options, Overrides, and iCloud Sync.
- [Status & Troubleshooting](/troubleshooting): status states, logs, and resources.
