# Shortcuts & Bookmarklet Setup Guide

Three quick automations that tie your iPhone, HomePod, and Mac directly into your Windows 11 media stack.

---

## 1. iPhone & Mac Share Sheet: "Send to Stash" (1-Tap Download)

Works both at home and remotely over cellular/Wi-Fi when **Tailscale** is enabled on your iPhone/Mac.

### Build in Apple Shortcuts (4 actions)
1. Open the **Shortcuts** app -> tap **+** -> name it **Send to Stash** (or something discreet like **Archive Link**).
2. Tap the **i (Details)** icon -> toggle ON **Show in Share Sheet** -> set **Receive** to **URLs** and **Safari web pages**.
3. Add these actions:
   - **Action 1: Get URLs from Input** (`Shortcut Input`)
   - **Action 2: Get Contents of URL**
     - **URL**: `http://<WIN11_TAILSCALE_IP>:8081/add` *(MeTube API endpoint)*
     - **Method**: `POST`
     - **Headers**: `Content-Type` = `application/json`
     - **Request Body**: `JSON`
       - Key `url` (Text): `URLs` *(output of Action 1)*
       - Key `quality` (Text): `best`
       - Key `format` (Text): `mp4`
   - **Action 3: Show Notification**
     - Text: `Queued download to library`

### Auto-Scan in Stash
In Stash (`http://<WIN11_IP>:9999`), go to **Settings -> Tasks -> Auto-Scan** (or install the community `AutoScan` / scheduled scan task) so anything MeTube finishes writing to `/data/inbox` automatically generates thumbnails, previews, and appears in Stash.

---

## 2. Desktop Browser Bookmarklet (1-Click Send to Stash)

Create a new bookmark in Safari/Chrome/Arc on your Mac or Windows PC and paste this as the **URL**:

```javascript
javascript:void(fetch('http://<WIN11_TAILSCALE_IP>:8081/add',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({url:window.location.href,quality:'best',format:'mp4'})}).then(()=>alert('Sent to MeTube -> Stash!')).catch(e=>alert('Failed: '+e)));
```

*(Note: If the site's Content-Security-Policy blocks `fetch` to an HTTP IP, use the macOS Share Sheet Shortcut above or open MeTube directly at `http://<WIN11_TAILSCALE_IP>:8081`.)*

---

## 3. Hands-Free Siri Voice Command: "Play on Plex"

Because Siri cannot natively search inside Plex, this Shortcut bridges Siri (iPhone or HomePod via Personal Requests) to your Home Assistant webhook.

### Build in Apple Shortcuts (3 actions)
1. Create a new Shortcut named **"Play on Plex"** (whatever you name the Shortcut becomes the exact Siri phrase: *"Hey Siri, Play on Plex"*).
2. Add these actions:
   - **Action 1: Ask for Input**
     - Prompt: `What movie should I play?`
     - Type: `Text`
   - **Action 2: Get Contents of URL**
     - **URL**: `http://<HA_LAN_IP>:8123/api/webhook/play_plex_title`
     - **Method**: `POST`
     - **Headers**: `Content-Type` = `application/json`
     - **Request Body**: `JSON`
       - Key `title` (Text): `Provided Input`
       - Key `library` (Text): `Movies`
   - **Action 3: Speak Text**
     - Text: `Starting Provided Input on the living room TV.`

3. **Enable on HomePod**: In the Apple **Home** app -> Home Settings -> tap your profile -> enable **Personal Requests** for your HomePod(s) so you can trigger this hands-free across the room!
