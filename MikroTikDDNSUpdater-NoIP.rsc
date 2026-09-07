#!rsc by RouterOS
# MikroTikDDNSUpdater-NoIP
# Build: 1
#
# https://github.com/lolostt/MikrotikDDNSUpdater
# Copyright (C) 2026 Sleeping Coconut https://sleepingcoconut.com
#
#
# This script updates DNS service using current public IP.
#
# Usage:
#    1. Fill "Variables" section below.
#    2. Place script in MikroTik device using Winbox, WebFig or terminal.
#    3. Give "read", "write" and "test" permissions.
#    4. You can automate execution using RouterOS scheduler. Check README.

# ============================================================================
# Variables (mandatory edit)
# ============================================================================

# No-IP account credentials. The username can be your No-IP email address.
:local noipUsername "user@example.com"
:local noipPassword "xxxxxxxxxxxxxxxx"

# All configured hostnames are updated sequentially. An error aborts the script.
:local records {
    "subdomain1.domain1.com";
    "subdomain2.domain2.com"
}

# Public IP services: 1 = icanhazip, 2 = ipify, 3 = Amazon.
:local publicIpService 1

# ============================================================================
# Hardcoded variables
# ============================================================================
# URL for No-IP Dynamic DNS update requests.
:local dnsNoipUrl "https://dynupdate.no-ip.com/nic/update"
# URL for public IP services
:local ipIcanhazipUrl "https://icanhazip.com"
:local ipIpifyUrl "https://api.ipify.org"
:local ipAmazonUrl "https://checkip.amazonaws.com"
# Placeholder values used to detect unedited configuration.
:local noipUsernamePlaceholder "user@example.com"
:local noipPasswordPlaceholder "xxxxxxxxxxxxxxxx"

# ============================================================================
# Runtime variables
# ============================================================================
:local publicIp
:local publicIpUrl ""

# ============================================================================
# Validate mandatory configuration
# ============================================================================
# Check that the No-IP credentials have been configured.
:if (([:len $noipUsername] = 0) || ($noipUsername = $noipUsernamePlaceholder)) do={
    :log error "MikroTikDDNSUpdater: edit noipUsername before running the script"
    :error "MikroTikDDNSUpdater: noipUsername is not configured"
}
:if (([:len $noipPassword] = 0) || ($noipPassword = $noipPasswordPlaceholder)) do={
    :log error "MikroTikDDNSUpdater: edit noipPassword before running the script"
    :error "MikroTikDDNSUpdater: noipPassword is not configured"
}

# Check that the selected public IP service is supported.
:if (($publicIpService < 1) || ($publicIpService > 3)) do={
    :log error ("MikroTikDDNSUpdater: invalid publicIpService = " . $publicIpService)
    :error "MikroTikDDNSUpdater: invalid publicIpService"
}

# Check that at least one DNS record has been configured.
:if ([:len $records] = 0) do={
    :log error "MikroTikDDNSUpdater: at least one DNS record is required"
    :error "MikroTikDDNSUpdater: records is empty"
}

# Validate every configured hostname before contacting No-IP.
:foreach configuredRecord in=$records do={
    :local configuredHostname $configuredRecord

    # Check that the hostname has been configured.
    :if (([:len $configuredHostname] = 0) || ($configuredHostname = "xxx")) do={
        :log error "MikroTikDDNSUpdater: edit the hostname in records before running the script"
        :error "MikroTikDDNSUpdater: hostname is not configured"
    }

}

# ============================================================================
# Get the public IP address
# ============================================================================
# Map the numeric selector to the corresponding provider URL.
:if ($publicIpService = 1) do={
    :set publicIpUrl $ipIcanhazipUrl
} else={
    # Select the ipify service.
    :if ($publicIpService = 2) do={
        :set publicIpUrl $ipIpifyUrl
    } else={
        # Select the Amazon service.
        :if ($publicIpService = 3) do={
            :set publicIpUrl $ipAmazonUrl
        } else={
            :log error ("MikroTikDDNSUpdater: invalid public IP service " . $publicIpService)
            :error "MikroTikDDNSUpdater: unable to select public IP service"
        }
    }
}

# Fetch the public IP address from the selected service.
:onerror publicIpFetchError in={
    :local publicIpResponse [/tool fetch url=$publicIpUrl output=user as-value]
    :set publicIp ($publicIpResponse->"data")
} do={
    :log error ("MikroTikDDNSUpdater: public IP request failed: " . $publicIpFetchError)
    :error "MikroTikDDNSUpdater: unable to fetch public IP"
}

:while ([:len $publicIp] > 0) do={
    :local lastCharacter [:pick $publicIp ([:len $publicIp] - 1)]

    :if (($lastCharacter = "\n") || ($lastCharacter = "\r")) do={
        :set publicIp [:pick $publicIp 0 ([:len $publicIp] - 1)]
    } else={
        :break
    }
}

:do {
    :set publicIp [:toip $publicIp]
} on-error={
    :log error ("MikroTikDDNSUpdater: invalid public IP: " . $publicIp)
    :error "MikroTikDDNSUpdater: unable to read public IP"
}

:log info ("MikroTikDDNSUpdater: current public IP is " . $publicIp)

# ============================================================================
# Update DNS records in No-IP.
# ============================================================================

:foreach configuredRecord in=$records do={
    :local configuredHostname $configuredRecord

    :onerror dnsUpdateError in={
        :local noipAuthorization ("Basic " . [:convert ($noipUsername . ":" . $noipPassword) from=raw to=base64])
        :local updateResponse [/tool fetch \
            url=($dnsNoipUrl . "?hostname=" . $configuredHostname . "&myip=" . $publicIp) \
            http-header-field=("User-Agent: MikroTikDDNSUpdater/1.0,Authorization: " . $noipAuthorization) \
            output=user as-value]
        :local responseData ($updateResponse->"data")

        :if (([:pick $responseData 0 4] != "good") && \
            ([:pick $responseData 0 5] != "nochg")) do={
            :log error ("MikroTikDDNSUpdater: No-IP rejected " . $configuredHostname . ": " . $responseData)
            :error "MikroTikDDNSUpdater: No-IP DNS update was not successful"
        }

        :if ([:pick $responseData 0 4] = "good") do={
            :log info ("MikroTikDDNSUpdater: updated " . $configuredHostname . " to " . $publicIp)
        } else={
            :log info ("MikroTikDDNSUpdater: no update required for " . $configuredHostname)
        }
    } do={
        :log error ("MikroTikDDNSUpdater: failed to update " . \
            $configuredHostname . " through No-IP: " . $dnsUpdateError)
        :error "MikroTikDDNSUpdater: No-IP DNS update failed"
    }
}