# MikrotikDDNSUpdater
A RouterOS script that keeps Cloudflare and/or No-IP DNS records pointing to the router's current public IPv4 address.

## Getting Started
### Prerequisites
#### Hardware
- Mikrotik device running RouterOS 7.23.4 or newer. Older versions (including RouterOS 6) are not supported.

#### Accounts
- **Cloudflare:** an API token with *Zone > DNS > Edit* permission, and the Zone ID of each domain (domain *Overview* page, *API* section). The A record must already exist.
- **No-IP:** the account email and password. The hostname must already exist in the account.

### Installing
1. Download, clone or copy `MikrotikDDNSUpdater.rsc` on your local computer.
2. Fill the "User configuration" block (see below).
3. Place the script in the Mikrotik device under System > Scripts using Winbox or WebFig.
4. Give it "read" and "test" permissions. They are the only ones it needs.
5. Run it once with `dryRun` set to `true` and check the log.
6. Set `dryRun` to `false` and automate execution using RouterOS scheduler. See below.

> **Security note:** if you add the script from the terminal (`/system script add ... source=...`), RouterOS writes the whole source, credentials included, to the system log. Paste it in Winbox or WebFig instead, and take extra care if the log is sent to a remote syslog server.

## Usage
You can run the script manually using Winbox or WebFig under System > Scripts section. Don't forget proper permissions.

<img width="871" height="836" alt="1" src="https://github.com/user-attachments/assets/93c77bab-c0d6-4a96-9c75-5edbac7f44ed" />


You can also run it from terminal:
```
/system script run MikrotikDDNSUpdater
```

### Configuration
- **records** (array): DNS records to keep updated, one entry per hostname. There can be one or several records per provider, and both providers can be mixed. Field names and hostnames must be lowercase (RouterOS reads an unquoted key with capitals, such as `zoneId=`, as a comparison).
    ```
    :local records {
        {provider="cloudflare"; hostname="home.example.com"; zoneid="<zone ID>"};
        {provider="noip"; hostname="home.ddns.net"}
    }
    ```
- **noipUsername** / **noipPassword** (string): No-IP account. Only needed for No-IP records.
- **cloudflareApiToken** (string): Cloudflare API token. Only needed for Cloudflare records.
- **dryRun** (boolean): `true` checks everything but does not change any DNS record. Enabled by default.
- **publicIpService** (string) selects the method for determining the current public IP address:
    - `auto` (default) tries every service in order until one answers: icanhazip, ipify, Amazon, ipinfo and Mikrotik.
    - `icanhazip`, `ipify`, `amazon`, `ipinfo` or `mikrotik` uses only that service. `mikrotik` reads IP > Cloud and only works if IP Cloud DDNS is already enabled.
- **checkCertificate** (string): TLS certificate check for HTTPS requests, `yes`, `yes-without-crl` (default) or `no`. `no` is not recommended because credentials travel in these requests. RouterOS built-in trust store is enough, no certificates need to be imported.

### Script behaviour
Script uses system log to show execution results and errors. Every message starts with `MikrotikDDNSUpdater:` followed by `INFO -`, `WARNING -` or `ERROR -`. If anything fails, the script ends with an error, so failures are never silent.

Script has 5 stages:
1. Configuration validation. Credentials are only required for the providers in use.
2. Get public IP address. Only valid public IPv4 addresses are accepted (private, CGNAT, loopback, multicast and reserved ranges are rejected).
3. Get the current IP address of each record: through Cloudflare API for Cloudflare, and by asking No-IP's own name server for No-IP.
4. IP addresses comparison.
5. Update of the records that need it. Cloudflare keeps proxy status and TTL. No-IP is only contacted when the IP has changed, as No-IP requires.

A record that fails does not stop the others: the remaining records are still processed and the script ends with an error.

If No-IP answers `badauth`, `nohost` or a similar error, fix the account or hostname as soon as possible: No-IP may block clients that keep sending failing updates.

Each run takes about one second and writes around 8 lines to the log. It does not write to flash storage, unless your logging configuration sends script messages to disk.

### Automation
You can automate execution in order to set and forget the script. You can do that by using RouterOS scheduler under System > Scheduler section. The scheduler entry needs the same "read" and "test" permissions. Running it every 15 minutes is recommended: it stays far below Cloudflare API limits and No-IP only receives a request when the IP changes.

```
/system scheduler add name=MikrotikDDNSUpdater interval=15m policy=read,test on-event="/system script run MikrotikDDNSUpdater"
```

<img width="545" height="733" alt="2" src="https://github.com/user-attachments/assets/54f66100-b7f9-494d-80c7-565a19202f5d" />

## Authors
* **lolost** - [sleepingcoconut.com](https://sleepingcoconut.com/)

## License
This project is licensed under the [Zero Clause BSD license](https://opensource.org/licenses/0BSD).
