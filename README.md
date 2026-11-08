# MikrotikDDNSUpdater
A RouterOS script that keeps DuckDNS, No-IP and/or Cloudflare DNS records pointing to the router's current public IPv4 address.

## Getting Started
### Prerequisites
#### Hardware
- Mikrotik device running RouterOS 7.23.4 or newer. Older versions (including RouterOS 6) are not supported.

#### Accounts
- **DuckDNS:** the account token, shown on the duckdns.org main page after signing in. The subdomain must already exist in the account.
- **No-IP:** the account email and password. The hostname must already exist in the account.
- **Cloudflare:** an API token with *Zone > DNS > Edit* permission, and the Zone ID of each domain (domain *Overview* page, *API* section). The A record must already exist.

### Installing
Whatever the method, the "User configuration" block at the top of the script has to be filled (see [Configuration](#configuration)):
- In `records`, replace the example entries with your own and remove the ones for providers you do not use.
- Fill the credentials of the providers you use. The others can keep their placeholder values.
- Leave `dryRun` set to `true` for now.

#### Method 1: from the terminal
1. Open a terminal on the router and run:
    ```
    /tool fetch url="https://raw.githubusercontent.com/lolostt/MikrotikDDNSUpdater/main/MikrotikDDNSUpdater.rsc" dst-path=MikrotikDDNSUpdater.rsc check-certificate=yes-without-crl
    /system script add name=MikrotikDDNSUpdater policy=read,test source=[/file get MikrotikDDNSUpdater.rsc contents]
    /file remove MikrotikDDNSUpdater.rsc
    ```
2. In Winbox or WebFig, go to System > Scripts, open `MikrotikDDNSUpdater` and fill the "User configuration" block in its source.
3. Go on with [First run and scheduling](#first-run-and-scheduling).

#### Method 2: from Winbox or WebFig
1. Download `MikrotikDDNSUpdater.rsc`, open it in a text editor and fill the "User configuration" block.
2. In Winbox or WebFig, go to System > Scripts and add a new script:
    - **Name:** `MikrotikDDNSUpdater`. The terminal and scheduler commands in this README use this name.
    - **Policy:** tick only `read` and `test`. They are the only ones the script needs.
    - **Don't Require Permissions:** leave it unticked.
    - **Source:** paste the whole content of the edited file.
3. Go on with [First run and scheduling](#first-run-and-scheduling).

#### First run and scheduling
1. Click *Run Script* and check the messages starting with `MikrotikDDNSUpdater:` under Log. With `dryRun` set to `true`, nothing is changed: the log shows the public IP address and, for each record, its current address and whether it needs an update. The dry-run `WARNING` lines are expected; fix any `ERROR` before going on.
2. Set `dryRun` to `false` in the script source and run it again. The log now shows, for each record, whether it was updated or was already up to date.
3. Schedule it to run automatically (see [Automation](#automation)).

To update to a newer build, keep a copy of your "User configuration" block, replace the source of the existing script with the new file and paste your block back. The script name and the scheduler entry stay the same.

> **Security note:** whenever the script is added or edited, from the terminal, Winbox or WebFig, RouterOS writes its whole source, credentials included, to the system log. Take extra care if the log is sent to a remote syslog server.

## Usage
You can run the script manually using Winbox or WebFig under System > Scripts section. Don't forget proper permissions.

<img width="871" height="836" alt="1" src="https://github.com/user-attachments/assets/93c77bab-c0d6-4a96-9c75-5edbac7f44ed" />


You can also run it from terminal:
```
/system script run MikrotikDDNSUpdater
```

### Configuration
- **records** (array): DNS records to keep updated, one entry per hostname. In interface mode, an entry can also carry an `interface` field. There can be one or several records per provider, and providers can be mixed. The hostname is always the full name, also for DuckDNS (`home.duckdns.org`, not `home`). Field names and hostnames must be lowercase (RouterOS reads an unquoted key with capitals, such as `zoneId=`, as a comparison).
    ```
    :local records {
        {provider="duckdns"; hostname="home.duckdns.org"};
        {provider="noip"; hostname="home.ddns.net"};
        {provider="cloudflare"; hostname="home.example.com"; zoneid="<zone ID>"}
    }
    ```
- **duckdnsToken** (string): DuckDNS account token (`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`). Only needed for DuckDNS records.
- **noipUsername** / **noipPassword** (string): No-IP account. Only needed for No-IP records.
- **cloudflareApiToken** (string): Cloudflare API token. Only needed for Cloudflare records.
- **dryRun** (boolean): `true` checks everything but does not change any DNS record. Enabled by default.
- **publicIpService** (string) selects the method for determining the current public IP address:
    - `auto` (default) tries every service in order until one answers: icanhazip, ipify, Amazon, ipinfo and Mikrotik.
    - `icanhazip`, `ipify`, `amazon`, `ipinfo` or `mikrotik` uses only that service. `mikrotik` reads IP > Cloud and only works if IP Cloud DDNS is already enabled.
    - `interface` reads the IPv4 address of a router interface instead of asking an external service (see [Interface mode](#interface-mode-multi-wan-and-cgnat)).
- **wanInterface** (string): only used with `publicIpService` set to `interface`. The interface that holds the public IPv4 address, such as `pppoe-out1`.
- **checkCertificate** (string): TLS certificate check for HTTPS requests, `yes`, `yes-without-crl` (default) or `no`. `no` is not recommended because credentials travel in these requests. RouterOS built-in trust store is enough, no certificates need to be imported.

### Interface mode (multi-WAN and CGNAT)
Setting `publicIpService` to `interface` makes the script read the public IP from a router interface instead of asking an external service. It is meant for routers whose WAN interface holds the public IPv4 address itself (PPPoE, or DHCP from an ONT in bridge mode):
- **Multi-WAN:** each record follows the interface you choose, not whichever WAN the default route uses at that moment. `wanInterface` is used by every record, and a record can follow another WAN by adding an `interface` field:
    ```
    :local records {
        {provider="noip"; hostname="home.ddns.net"};
        {provider="cloudflare"; hostname="backup.example.com"; zoneid="<zone ID>"; interface="ether2"}
    }
    :local publicIpService "interface"
    :local wanInterface "pppoe-out1"
    ```
- **CGNAT and double NAT detection:** if the interface has a CGNAT address (`100.64.0.0/10`), the log says the ISP shares the public IP and the router cannot be reached from the Internet. If it has a private address, the router is behind another NAT device and `publicIpService` must stay `auto`. In both cases the records on that interface are not updated and the script ends with an error.

Use the name of the interface that holds the address (IP > Addresses): `pppoe-out1` rather than the Ethernet port under it, or the bridge or VLAN if the address is set there. The `interface` field is only accepted in this mode.

### Script behaviour
Script uses system log to show execution results and errors. Every message starts with `MikrotikDDNSUpdater:` followed by `INFO -`, `WARNING -` or `ERROR -`. If anything fails, the script ends with an error, so failures are never silent.

Script has 5 stages:
1. Configuration validation. Credentials are only required for the providers in use.
2. Get public IP address, from the external services or, in interface mode, from each record's interface. Only valid public IPv4 addresses are accepted (private, CGNAT, loopback, multicast and reserved ranges are rejected).
3. Get the current IP address of each record: through Cloudflare API for Cloudflare, and by asking each provider's own name server for No-IP and DuckDNS.
4. IP addresses comparison.
5. Update of the records that need it. Cloudflare keeps proxy status and TTL. No-IP and DuckDNS are only contacted when the IP has changed.

A record that fails does not stop the others: the remaining records are still processed and the script ends with an error.

If No-IP answers `badauth`, `nohost` or a similar error, fix the account or hostname as soon as possible: No-IP may block clients that keep sending failing updates.

If DuckDNS answers `KO`, the token is wrong or the subdomain does not belong to the account. DuckDNS gives no other detail.

Each run takes about one second and writes around 8 lines to the log. It does not write to flash storage, unless your logging configuration sends script messages to disk.

### Automation
You can automate execution in order to set and forget the script. You can do that by using RouterOS scheduler under System > Scheduler section. The scheduler entry needs the same "read" and "test" permissions. Running it every 15 minutes is recommended: it stays far below Cloudflare API limits and No-IP and DuckDNS only receive a request when the IP changes.

```
/system scheduler add name=MikrotikDDNSUpdater interval=15m policy=read,test on-event="/system script run MikrotikDDNSUpdater"
```

<img width="545" height="733" alt="2" src="https://github.com/user-attachments/assets/54f66100-b7f9-494d-80c7-565a19202f5d" />

## Authors
* **lolost** - [sleepingcoconut.com](https://sleepingcoconut.com/)

## License
This project is licensed under the [Zero Clause BSD license](https://opensource.org/licenses/0BSD).
