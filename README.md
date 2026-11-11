# MikroTikDDNSUpdater
A RouterOS script that keeps DuckDNS, No-IP, Dynu, FreeDNS and/or Cloudflare DNS records pointing to the router's current public IPv4 address.

## Getting Started
### Prerequisites
#### Requirements
- MikroTik device running RouterOS 7.23.4 or newer. Older versions (including RouterOS 6) are not supported.

#### Accounts
- **DuckDNS:** the account token, shown on the duckdns.org main page after signing in. The subdomain must already exist in the account.
- **No-IP:** the account email and password. The hostname must already exist in the account.
- **Dynu:** the account username and the IP Update Password (*Control Panel > My Account > Username/Password*), or its MD5 or SHA-256 hash. Do not use the account password: the IP Update Password only allows IP updates. The hostname must already exist in the account.
- **FreeDNS:** the update token of each record: in *Dynamic DNS*, the part after `/u/` in its version 2 update URL (`https://sync.afraid.org/u/<token>/`). The A record must already exist.
- **Cloudflare:** an API token with *Zone > DNS > Edit* permission, and the Zone ID of each domain (domain *Overview* page, *API* section). The A record must already exist. Under *Zone Resources*, limit the token to the zones of your records (*Include > Specific zone*), not *All zones*: the token is stored in the script, and a token for every zone would let anyone who reads it redirect any domain of the account. If the router has a fixed public IP, *Client IP Address Filtering* can also limit the token to it.

### Installing
Whatever the method, the "User configuration" block at the top of the script has to be filled (see [Configuration](#configuration)):
- In `records`, replace the example entries with your own and remove the ones for providers you do not use.
- Fill the credentials of the providers you use. The others can keep their placeholder values.
- Leave `dryRun` set to `true` for now.

#### Method 1: from the terminal
1. Open a terminal on the router and run:
    ```
    /tool fetch url="https://raw.githubusercontent.com/lolostt/MikroTikDDNSUpdater/main/MikroTikDDNSUpdater.rsc" dst-path=MikroTikDDNSUpdater.rsc check-certificate=yes-without-crl
    :local source [/file get MikroTikDDNSUpdater.rsc contents]; :if ([:len $source] = 0) do={:error "MikroTikDDNSUpdater.rsc could not be read"}; /system script add name=MikroTikDDNSUpdater policy=read,test source=$source
    /file remove MikroTikDDNSUpdater.rsc
    ```
    RouterOS reads files of up to 61439 bytes this way and returns nothing for larger ones; the second line stops with an error instead of adding an empty script.
2. In Winbox or WebFig, go to System > Scripts, open `MikroTikDDNSUpdater` and fill the "User configuration" block in its source.
3. Go on with [First run and scheduling](#first-run-and-scheduling).

#### Method 2: from Winbox or WebFig
1. Download `MikroTikDDNSUpdater.rsc`, open it in a text editor and fill the "User configuration" block.
2. In Winbox or WebFig, go to System > Scripts and add a new script:
    - **Name:** `MikroTikDDNSUpdater`. The terminal and scheduler commands in this README use this name.
    - **Policy:** tick only `read` and `test`. They are the only ones the script needs.
    - **Don't Require Permissions:** leave it unticked.
    - **Source:** paste the whole content of the edited file.
3. Go on with [First run and scheduling](#first-run-and-scheduling).

#### First run and scheduling
1. Click *Run Script* and check the messages starting with `MikroTikDDNSUpdater:` under Log. With `dryRun` set to `true`, nothing is changed: the log shows the public IP address and, for each record, its current address and whether it needs an update. The dry-run `WARNING` lines are expected; fix any `ERROR` before going on.
2. Set `dryRun` to `false` in the script source and run it again. The log now shows, for each record, whether it was updated or was already up to date. DuckDNS, No-IP, Dynu and FreeDNS credentials are only used when a record needs an update, so a wrong one shows up in the log the first time that happens.
3. Schedule it to run automatically (see [Automation](#automation)).

To update to a newer build, keep a copy of your "User configuration" block, replace the source of the existing script with the new file and paste your block back. The script name and the scheduler entry stay the same.

> **Security note:** credentials are stored in plain text in the script source. Whenever the script is added or edited, from the terminal, Winbox or WebFig, RouterOS writes its whole source, credentials included, to the system log. Take extra care if the log is sent to a remote syslog server. `/export` and backups of the configuration also carry the credentials, so keep them private.

## Usage
You can run the script manually using Winbox or WebFig under System > Scripts section.

<img width="871" height="836" alt="Script in Winbox" src="https://github.com/user-attachments/assets/b6ec597a-7e41-4b09-a06a-3a36b627c1f3" />


You can also run it from terminal:
```
/system script run MikroTikDDNSUpdater
```

### Configuration
Write every text value between double quotes. Inside them, RouterOS reads `$` as the start of a variable, `"` as the end of the value and `\` as an escape character, and changes the value without any error: a password with any of these characters would be sent wrong and rejected with `badauth`. Write them as `\$`, `\"` and `\\`. For example, the password `Pa$s"w\d` goes as `"Pa\$s\"w\\d"`.

- **records** (array): DNS records to keep updated, one entry per hostname. In interface mode, an entry can also carry an `interface` field. There can be one or several records per provider, and providers can be mixed. The hostname is always the full name, also for DuckDNS (`home.duckdns.org`, not `home`). Field names and hostnames must be lowercase (RouterOS reads an unquoted key with capitals, such as `zoneId=`, as a comparison).
    ```
    :local records {
        {provider="duckdns"; hostname="SUBDOMAIN.DOMAIN.COM"};
        {provider="noip"; hostname="SUBDOMAIN.DOMAIN.COM"};
        {provider="dynu"; hostname="SUBDOMAIN.DOMAIN.COM"};
        {provider="freedns"; hostname="SUBDOMAIN.DOMAIN.COM"; token="FREEDNS_TOKEN"};
        {provider="cloudflare"; hostname="SUBDOMAIN.DOMAIN.COM"; zoneid="CLOUDFLARE_ZONE_ID"}
    }
    ```
    FreeDNS records carry their own `token` (letters and digits); Cloudflare records carry their `zoneid`.
- **duckdnsToken** (string): DuckDNS account token (`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`). Only needed for DuckDNS records.
- **noipUsername** / **noipPassword** (string): No-IP account. Only needed for No-IP records.
- **dynuUsername** / **dynuPassword** (string): Dynu account username and IP Update Password (or its MD5 or SHA-256 hash), not the account password. Only needed for Dynu records.
- **cloudflareApiToken** (string): Cloudflare API token. Only needed for Cloudflare records.
- **dryRun** (boolean): `true` checks the configuration, gets the public IP and reads every record, but does not change any DNS record. Enabled by default. Only the Cloudflare token is tested, because it is needed to read Cloudflare records: DuckDNS, No-IP, Dynu and FreeDNS credentials are only checked for their format, and are first sent when a record needs an update.
- **publicIpService** (string) selects the method for determining the current public IP address:
    - `auto` (default) tries every service in order until one answers: icanhazip, ipify, Amazon, ipinfo and MikroTik.
    - `icanhazip`, `ipify`, `amazon`, `ipinfo` or `mikrotik` uses only that service. `mikrotik` reads IP > Cloud and only works if IP Cloud DDNS is already enabled.
    - `interface` reads the IPv4 address of a router interface instead of asking an external service (see [Interface mode](#interface-mode-multi-wan-and-cgnat)).
- **wanInterface** (string): only used with `publicIpService` set to `interface`. The interface that holds the public IPv4 address, such as `pppoe-out1`. With PPPoE, set the name of the PPPoE interface (e.g. `pppoe-out1`), not the Ethernet port it runs on (e.g. `ether1`). Records with their own `interface` field do not use it, so it can keep its placeholder value `WAN_INTERFACE` if every record has one.
- **checkCertificate** (string): TLS certificate check for HTTPS requests, `yes`, `yes-without-crl` (default) or `no`. `no` is not recommended because credentials travel in these requests. RouterOS built-in trust store is enough, no certificates need to be imported.

### Interface mode (multi-WAN and CGNAT)
Setting `publicIpService` to `interface` makes the script read the public IP from a router interface instead of asking an external service. It is meant for routers whose WAN interface holds the public IPv4 address itself (PPPoE, or DHCP from an ONT in bridge mode). On those routers it is the recommended mode: it does not depend on third-party services, and it cannot pick a wrong address when the router's traffic leaves through a VPN or a backup WAN, as an external service would see the address of that path instead. It also covers:
- **Multi-WAN:** with two or more WANs, different records can take their IP from different interfaces. Each record follows a fixed interface, not whichever WAN the default route uses at that moment:
    - `wanInterface` sets the interface for every record that does not say otherwise.
    - A record that must follow another WAN gets an `interface` field inside its own entry in `records`, next to `provider` and `hostname`.
    - The `interface` field only works with `publicIpService` set to `interface`. In any other mode, a record with it is reported as an error.

    Example with two WANs: `home.duckdns.org` takes the IP of `pppoe-out1` (from `wanInterface`, as it has no `interface` field), and `office.ddns.net` takes the IP of `ether2`:
    ```
    :local records {
        {provider="duckdns"; hostname="home.duckdns.org"};
        {provider="noip"; hostname="office.ddns.net"; interface="ether2"}
    }
    :local publicIpService "interface"
    :local wanInterface "pppoe-out1"
    ```
    If every record has its own `interface` field, `wanInterface` is not used and can keep its placeholder value `WAN_INTERFACE`.
- **CGNAT and double NAT detection:** if the interface has a CGNAT address (`100.64.0.0/10`), the log says the ISP shares the public IP and the router cannot be reached from the Internet. If it has a private address, the router is behind another NAT device and `publicIpService` must stay `auto`. A link-local address (`169.254.0.0/16`) means the interface got no address from the ISP. In all these cases the records on that interface are not updated and the script ends with an error.

Use the name of the interface that holds the address (IP > Addresses). With PPPoE, that is the PPPoE interface (e.g. `pppoe-out1`), not the Ethernet port or VLAN it runs on; if the Ethernet port or VLAN is set by mistake, the log names the PPPoE client to use instead. Without PPPoE, use the Ethernet port, bridge or VLAN that holds the address. This applies to `wanInterface` and to the `interface` field alike.

### Script behaviour
Script uses system log to show execution results and errors. Every message starts with `MikroTikDDNSUpdater:` followed by `INFO -`, `WARNING -` or `ERROR -`. If anything fails, the script ends with an error, so failures are never silent.

Script has 5 stages:
1. Configuration validation. Credentials are only required for the providers in use.
2. Get public IP address, from the external services or, in interface mode, from each record's interface. Only valid public IPv4 addresses are accepted (private, CGNAT, loopback, link-local, documentation, multicast and reserved ranges are rejected).
3. Get the current IP address of each record: through Cloudflare API for Cloudflare, and by asking each provider's own name server for DuckDNS, No-IP, Dynu and FreeDNS. If that server cannot be reached, the router's DNS is asked instead, with a warning: it may still hold the old IP for a while, which at worst sends one unneeded update.
4. IP addresses comparison.
5. Update of the records that need it. Cloudflare keeps proxy status and TTL. DuckDNS, No-IP, Dynu and FreeDNS are only contacted when the IP has changed. While the script runs, DuckDNS and FreeDNS tokens never appear in the log (see the security note in [First run and scheduling](#first-run-and-scheduling) for what happens when the script is edited).

A record that fails does not stop the others: the remaining records are still processed and the script ends with an error.

If No-IP answers `badauth`, `nohost` or a similar error, fix the account or hostname as soon as possible: No-IP may block clients that keep sending failing updates. The script keeps no state between runs, so every scheduled run sends the failing update again while the IP differs: if the fix has to wait, disable the scheduler entry (`/system scheduler disable MikroTikDDNSUpdater`) and enable it again afterwards.

Dynu uses the same answers as No-IP (`good`, `nochg`, `badauth`, `nohost`...) and the same advice applies. If it answers `911`, its servers have a problem: the next scheduled run tries again.

If FreeDNS answers that it could not find any matching DNS records, the token is wrong. With FreeDNS *linked updates* (on by default), updating a record also updates the other records of the account that had the same IP.

If DuckDNS answers `KO`, the token is wrong or the subdomain does not belong to the account. DuckDNS gives no other detail.

Each run takes about one second and writes about 3 lines to the log, plus 2 per record. It does not write to flash storage, unless your logging configuration sends script messages to disk.

A run cannot last until the next scheduled one: each request gives up after about 10 seconds without an answer. Running the script by hand while the scheduler also runs it is harmless, as both runs send the same updates.

### Automation
To set and forget the script, run it with the RouterOS scheduler under System > Scheduler. The scheduler entry needs the same "read" and "test" permissions. Running it every 15 minutes is recommended: it stays far below Cloudflare API limits and DuckDNS, No-IP, Dynu and FreeDNS only receive a request when the IP changes.

```
/system scheduler add name=MikroTikDDNSUpdater interval=15m policy=read,test on-event="/system script run MikroTikDDNSUpdater"
```

<img width="545" height="733" alt="Scheduler entry" src="https://github.com/user-attachments/assets/f44379b5-85fb-44c0-9247-9446ded7bd5c" />

## Authors
* **lolost** - [sleepingcoconut.com](https://sleepingcoconut.com/)

## License
This project is licensed under the [MIT License](LICENSE).
