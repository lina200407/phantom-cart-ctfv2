# Security Guide — Operation Phantom Cart Workshop Server

## Before you run anything on the university network, read this.

---

## What risks exist and what we fixed

### Risk 1 — Anyone on the network could access the CTF
**Problem:** `python3 -m http.server` has zero access control.
**Fix:** `server.py` requires an access code before serving any file.
Only participants you give the code to can reach the challenges.

### Risk 2 — The presenter answer key is publicly accessible
**Problem:** `PRESENTER_ANSWERS.md` contains all flags and solutions.
**Fix:** `server.py` blocks `/PRESENTER_ANSWERS.md` with a hard 403 —
no authentication bypass can reach it.

### Risk 3 — Stored XSS affects other real participants
**Problem:** Challenge 6 (stored XSS) lets participants inject scripts
that execute in other visitors' browsers. In a shared session this means
participant A can run JS in participant B's browser.
**Fix:** The challenge uses in-memory JS storage (no real persistence).
Each participant's browser has its own isolated state.
The injected scripts only affect the person who injected them.

### Risk 4 — A participant submits real card data to the skimmer
**Problem:** The skimmer demo sends form data to webhook.site.
Someone might type a real card number "just to see what happens."
**Fix:** Add a prominent fake data notice (already in the HTML).
Change the card number field placeholder to "USE: 4111 1111 1111 1111".
The webhook.site URL should be one you control and clear after the demo.

### Risk 5 — Brute force / scanning from other students on the network
**Problem:** Someone curious on the university network finds your server
and starts scanning or fuzzing it.
**Fix:** `server.py` rate-limits to 60 requests/minute per IP.
Exceeding this returns 429 and logs the IP.

### Risk 6 — Your laptop's other services are exposed
**Problem:** Running a server on port 8080 doesn't isolate it from
other ports on your machine.
**Fix:** See the firewall section below.

---

## How to run securely

### Step 1 — Use the hardened server, not python -m http.server
```bash
cd ctf/
python3 server.py
```

### Step 2 — Set your access code
Open `server.py` and change:
```python
ACCESS_CODE = "phantom2026"   # change this to something you choose
```
Give this code verbally to participants at the start of the lab.
Don't write it on the projector.

### Step 3 — Optional: restrict to your classroom subnet only
If your classroom uses, e.g., 192.168.10.x:
```python
IP_ALLOWLIST = ["192.168.10.0/24"]
```
This blocks anyone outside that subnet from even reaching the login page.

### Step 4 — Firewall your laptop (Linux)
Allow only your workshop port, block everything else inbound:
```bash
sudo ufw enable
sudo ufw allow 8080/tcp
sudo ufw deny in from any to any
sudo ufw allow in from 192.168.10.0/24    # your classroom subnet
```
Undo after the workshop:
```bash
sudo ufw reset
```

### Step 5 — Find your laptop's IP to share with participants
```bash
hostname -I       # Linux
ipconfig          # Windows
```
Share: http://[your-ip]:8080

### Step 6 — Monitor the access log during the session
```bash
tail -f workshop_access.log
```
You'll see every IP and request in real time.

---

## What the CTF intentionally does NOT protect against
(by design — these are the educational vulnerabilities)

- XSS in challenges 4 and 6 — intentional
- IDOR in challenge 5 — intentional (fake data only)
- Missing CSP on challenge pages — intentional (the lesson IS the missing CSP)

These are safe because:
1. All "data" is hardcoded fake data — no real database
2. Stored XSS uses in-browser JS arrays, not a real server — state resets on reload
3. The IDOR "passengers" are fictional characters with fictional passports

---

## Absolute rules for the day

1. Tell participants at the start: "Only attack the CTF server. Do not scan or probe the university network or any other host."
2. Do not connect the CTF server to any real database or real API.
3. Use a dedicated webhook.site URL for the skimmer demo — clear it after the demo, before the lab.
4. Stop the server with Ctrl+C immediately after the workshop ends.
5. Delete `workshop_access.log` after the event (it contains participant IPs).

---

## Emergency: if something goes wrong during the workshop

Stop the server instantly:
```
Ctrl+C
```

If a participant is scanning the university network (not just your server):
- Note their IP from `workshop_access.log`
- Stop your server
- Report to your university IT security contact

---

## Checklist before going live

- [ ] Changed ACCESS_CODE from the default
- [ ] Replaced WEBHOOK_URL with your own webhook.site URL
- [ ] Tested server.py locally before the event
- [ ] PRESENTER_ANSWERS.md returns 403 when accessed in browser
- [ ] Firewall rules applied on your laptop (if on a large university network)
- [ ] Participants briefed: "only attack the CTF server"
- [ ] You know how to stop the server instantly (Ctrl+C)
