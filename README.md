

# MikrotikDDNSUpdater
This is a set of scripts. Each script updates specific dynamic DNS service using current public IP.

## Getting Started
### Prerequisites
#### Hardware
- Mikrotik device running RouterOS 6. RouterOS 7 compatibility is not tested yet.

### Installing
1. Download, clone or copy script on your local computer.
2. Fill "Variables" section.
4. Place script in Mikrotik device using Winbox, WebFig or terminal.
5. Give "read", "write" and "test" permissions.
5. You can automate execution using RouterOS scheduler. See below.

## Usage
You can run the script manually using Winbox or WebFig under System > Scripts section. Don't forget proper permissions. You can also run it from terminal:
```
/system script run MikroTikDDNSUpdater
```
### Available options
- DDNSService (integer) variable lets you select dynamic DNS service. Note that different services requires different types of credentials.
-- Service 1: DNS-O-Matic. Requires DDNSUserName and DDNSUserPassword.
-- Service 2: No-IP. Requires DDNSUserName and DDNSUserPassword.
- PublicIPServiceMode (integer) variable lets you select method of determining current public IP address: 
-- Method 1 uses OpenDNS service.
-- Method 2 uses Mikrotik Cloud service. Requires MikroTikCloudHostName.
- VerboseMode variable (boolean) lets you activate verbose mode.

### Script behaviour
Script uses system log to show execution results and errors.
Script has 4 stages:
1. Variable check: looks for defaults.
2. Get public IP address.
3. Get domain IP address.
4. IP addresses comparison and DDNS API call.


## Authors
* **lolost** - [sleepingcoconut.com](https://sleepingcoconut.com/)

## License
This project is licensed under the [Zero Clause BSD license](https://opensource.org/licenses/0BSD).