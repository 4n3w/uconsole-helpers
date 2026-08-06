# Wifi on the uConsole

**Wifi is off by default and does not come up at boot.** Run `wifi on` when you want it.

## The `wifi` command

```bash
wifi            # fzf menu
wifi on         # link up, associate, get a DHCP lease
wifi off        # release lease, stop daemons, link down
wifi status     # link state, daemon, address, configured networks
wifi restart    # off then on
wifi edit       # edit wpa_supplicant.conf, restart if it was up
wifi add SSID   # append a network, prompting for the passphrase
```

`~/.local/bin/wifi` is a symlink to `~/uconsole/bin/wifi`, so it is tracked in this repo.
Note that `~/uconsole` is itself a symlink to the checkout — see the main `CLAUDE.md`.
The script contains no SSIDs and no passphrase; it only starts and stops daemons.

## How it is wired

`wlan0` is **not** managed by NetworkManager. It is driven directly by
`wpa_supplicant` reading `/etc/wpa_supplicant/wpa_supplicant.conf`, which is the single
source of truth for the network and its passphrase.

```
/etc/NetworkManager/conf.d/10-uconsole-wlan0-unmanaged.conf   keeps NM off wlan0
/etc/wpa_supplicant/wpa_supplicant.conf                        network + passphrase, mode 600
/run/wpa_supplicant-wlan0.pid                                  our daemon (not NM's)
```

`wifi on` is just:

```bash
ip link set wlan0 up
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf -P /run/wpa_supplicant-wlan0.pid
dhclient -1 -pf /run/dhclient-wlan0.pid wlan0
```

Nothing is enabled at boot, so `wlan0` simply stays down until asked.

## Adding a network

```bash
wifi add "Some Network"     # prompts for the passphrase
```

Appends a block and restarts if wifi was already up. `wpa_supplicant` tries every
configured network and associates with whichever is in range, so adding one never
disturbs the others.

The passphrase is never an argument and never a shell variable — `wpa_passphrase` reads
it straight from the terminal and its output is piped directly to the file, so it reaches
neither shell history nor `/proc/<pid>/cmdline`. Only the salted hash is written; the
`#psk="..."` plaintext comment that `wpa_passphrase` emits is stripped mid-pipe.

Refuses to add an SSID that is already configured — a duplicate block is worse than an
error, because `wpa_supplicant` would silently use whichever it reached first. Use
`wifi edit` to change an existing one. The previous config is saved to
`wpa_supplicant.conf.bak` on every add, and restored automatically if `wpa_passphrase`
rejects the passphrase (it requires 8-63 characters).

## Changing networks by hand

Edit the config; that is the only place it lives:

```bash
wifi edit
```

A network block looks like:

```
network={
    ssid="Some Network"
    psk=<64-hex hash, or "plaintext passphrase">
    key_mgmt=WPA-PSK
    ieee80211w=0
}
```

To generate a hash rather than storing plaintext:

```bash
wpa_passphrase "Some Network"
# type the passphrase, Enter, Ctrl-D
```

Do not pass the passphrase as a second argument — that puts it in shell history.
The output includes a commented `#psk="..."` plaintext line; delete it before saving.
**The hash is salted with the SSID**, so changing the SSID means regenerating it.

## Notes

- `Supreme Authority` is WPA3. This box has wpa_supplicant 2.9, whose SAE/PMF support
  is fussy. `Supreme PMF-off` is the WPA2 network and is what is configured.
- Wifi lands on a different subnet (192.168.7.x) than the wired USB adapter
  (192.168.10.x).
- NetworkManager still runs and still owns `eth0`/`eth1`. It also runs its own global
  `wpa_supplicant -u -s`; that is unrelated to ours and must not be killed. The script
  tracks its own daemon by pidfile precisely so a stray `pkill` cannot hit NM's.
- Two things NetworkManager does *not* do here: it never reads
  `/etc/wpa_supplicant/wpa_supplicant.conf`, and `nmcli` is not the tool for wifi on
  this box. Use `wifi`.
