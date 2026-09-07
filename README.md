

# MikrotikDDNSUpdater
This is a set of scripts. Each script updates specific DNS service using current public IP.

## Getting Started
### Prerequisites
#### Hardware
- Mikrotik device running RouterOS 7.1 or newer. RouterOS 6 is not supported.

### Installing
1. Download, clone or copy script on your local computer.
2. Fill "Variables" section.
4. Place script in Mikrotik device using Winbox, WebFig or terminal.
5. Give "read", "write" and "test" permissions.
5. You can automate execution using RouterOS scheduler. See below.

## Usage
You can run the script manually using Winbox or WebFig under System > Scripts section. Don't forget proper permissions.

<img width="761" height="824" alt="1" src="https://github.com/user-attachments/assets/d7a3b529-f896-4d63-b285-aecd69762733" />


You can also run it from terminal:
```
/system script run MikroTikDDNSUpdater-Cloudflare
```

### Available options
- **PublicIPServiceMode** (integer) variable allows you to select the method for determining the current public IP address: 
    1. Method 1 uses icanhazip.com service.
    2. Method 2 uses ipify.org service.
    3. Method 3 uses Amazon service.


### Script behaviour
Script uses system log to show execution results and errors.
Script has 4 stages:
1. Configuration validation.
2. Get public IP address.
3. Get domain IP address.
4. IP addresses comparison and DNS API call.

### Automation
You can automate execution in order to set and forget the script. You can do that by using RouterOS scheduler under System > Scheduler section. Don't forget proper permissions.

<img width="525" height="720" alt="2" src="https://github.com/user-attachments/assets/5475b0d5-7819-48c4-8dfc-9250f4d03735" />

## Authors
* **lolost** - [sleepingcoconut.com](https://sleepingcoconut.com/)

## License
This project is licensed under the [Zero Clause BSD license](https://opensource.org/licenses/0BSD).
