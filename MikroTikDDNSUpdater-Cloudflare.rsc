#!rsc by RouterOS
# MikroTikDDNSUpdater-Cloudflare
# Build: 10
#
# https://github.com/lolostt/MikrotikDDNSUpdater
# Copyright (C) 2026 Sleeping Coconut https://sleepingcoconut.com
#
#
# This script updates DNS service using current public IP.
# Requires RouterOS 7.13 or newer.
#
# Usage:
#    1. Fill "Variables" section below.
#    2. Place script in MikroTik device using Winbox, WebFig or terminal.
#    3. Give "read", "write" and "test" permissions.
#    4. You can automate execution using RouterOS scheduler. Check README.

# ============================================================================
# Variables (mandatory edit)
# ============================================================================

# Cloudflare API token with permissions to edit DNS records. Zone ID for the domain to be updated.
:local cfToken "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
:local zoneId "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# All configured records are checked and updated sequentially. An error aborts the script.
# Format:
#   {"hostname","record_id","proxied"}
# proxied:
#   true  = proxied through Cloudflare
#   false = DNS only
:local records {
    {"subdomain1.domain1.com";"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";true};
    {"subdomain2.domain2.com";"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";false}
}

# Public IP services: 1 = icanhazip, 2 = ipify, 3 = Amazon.
:local publicIpService 1

# ============================================================================
# Hardcoded variables
# ============================================================================
# URL for DNS update requests to Cloudflare API
:local dnsCloudflareUrl ("https://api.cloudflare.com/client/v4/zones/" . $zoneId . "/dns_records/")
# Headers for DNS update requests to Cloudflare API
:local cloudflareHeaders ("Authorization: Bearer " . $cfToken . ",Content-Type: application/json")
# URL for public IP services
:local ipIcanhazipUrl "https://icanhazip.com"
:local ipIpifyUrl "https://api.ipify.org"
:local ipAmazonUrl "https://checkip.amazonaws.com"
# Placeholder values used to detect unedited configuration.
:local cfTokenPlaceholder "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
:local zoneIdPlaceholder "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
:local recordIdPlaceholder "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# ============================================================================
# Runtime variables
# ============================================================================
:local publicIp
:local publicDNSIp ({})
:local publicIpUrl ""

# ============================================================================
# Validate mandatory configuration
# ============================================================================
# Reject the default token placeholder before making external requests.
# Check that the Cloudflare token has been configured.
:if (([:len $cfToken] = 0) || ($cfToken = $cfTokenPlaceholder)) do={
    :log error "MikroTikDDNSUpdater: edit cfToken before running the script"
    :error "MikroTikDDNSUpdater: cfToken is not configured"
}

# Reject the default zone placeholder before building API requests.
# Check that the Cloudflare zone ID has been configured.
:if (([:len $zoneId] = 0) || ($zoneId = $zoneIdPlaceholder)) do={
    :log error "MikroTikDDNSUpdater: edit zoneId before running the script"
    :error "MikroTikDDNSUpdater: zoneId is not configured"
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

# Validate every configured record before contacting Cloudflare.
:foreach configuredRecord in=$records do={
    :local configuredHostname [:pick $configuredRecord 0]
    :local configuredRecordId [:pick $configuredRecord 1]
    :local configuredProxied [:pick $configuredRecord 2]

    # Check that the hostname has been configured.
    :if (([:len $configuredHostname] = 0) || ($configuredHostname = "xxx")) do={
        :log error "MikroTikDDNSUpdater: edit the hostname in records before running the script"
        :error "MikroTikDDNSUpdater: hostname is not configured"
    }

    # Check that the DNS record ID has been configured.
    :if (([:len $configuredRecordId] = 0) || \
        ($configuredRecordId = $recordIdPlaceholder)) do={
        :log error ("MikroTikDDNSUpdater: edit record_id for " . $configuredHostname)
        :error "MikroTikDDNSUpdater: record_id is not configured"
    }

    # Check that the proxy setting is a Boolean value.
    :if (($configuredProxied != true) && ($configuredProxied != false)) do={
        :log error ("MikroTikDDNSUpdater: invalid proxied value for " . $configuredHostname)
        :error "MikroTikDDNSUpdater: invalid proxied value"
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
# Get the public IP address for each configured DNS record.
# ============================================================================

:for recordIndex from=0 to=([:len $records] - 1) do={
    :set publicDNSIp ($publicDNSIp , "")
}

:foreach recordIndex,configuredRecord in=$records do={
    :local configuredHostname [:pick $configuredRecord 0]
    :local configuredRecordId [:pick $configuredRecord 1]

    :onerror dnsReadError in={
        :local dnsRecordResponse [/tool fetch \
            url=($dnsCloudflareUrl . $configuredRecordId) \
            http-method=get \
            http-header-field=$cloudflareHeaders \
            output=user as-value]
        :if (($dnsRecordResponse->"code") != 200) do={
            :log error ("MikroTikDDNSUpdater: DNS GET failed for " . \
                $configuredHostname . ": HTTP status " . ($dnsRecordResponse->"code"))
            :error ("HTTP status " . ($dnsRecordResponse->"code"))
        }
        :local dnsRecordJson [:deserialize from=json \
            value=($dnsRecordResponse->"data")]
        :local dnsRecordResult ($dnsRecordJson->"result")

        :if (($dnsRecordJson->"success") != true) do={
            :log error ("MikroTikDDNSUpdater: Cloudflare returned success=false for " . \
                $configuredHostname)
            :error "MikroTikDDNSUpdater: Cloudflare API returned success=false"
        }

        :if ([:typeof $dnsRecordResult] = "nil") do={
            :log error ("MikroTikDDNSUpdater: no result for " . $configuredHostname)
            :error "MikroTikDDNSUpdater: invalid DNS record response"
        }

        :if (($dnsRecordResult->"name") != $configuredHostname) do={
            :log error ("MikroTikDDNSUpdater: record name mismatch for " . $configuredHostname)
            :error ("MikroTikDDNSUpdater: Cloudflare record name does not match " . $configuredHostname)
        }

        :local resolvedDnsIp [:toip ($dnsRecordResult->"content")]
        :if ([:typeof $resolvedDnsIp] != "ip") do={
            :log error ("MikroTikDDNSUpdater: empty DNS IP for " . $configuredHostname)
            :error "MikroTikDDNSUpdater: DNS record content is not an IP"
        }
        :set ($publicDNSIp->$recordIndex) $resolvedDnsIp

        :log info ("MikroTikDDNSUpdater: " . $configuredHostname . \
            " has DNS IP " . ($publicDNSIp->$recordIndex))
    } do={
        :log error ("MikroTikDDNSUpdater: failed to read " . $configuredHostname . \
            " from Cloudflare: " . $dnsReadError)
        :error "MikroTikDDNSUpdater: Cloudflare DNS lookup failed"
    }
}

# ============================================================================
# Update DNS records in Cloudflare when required.
# ============================================================================

:foreach recordIndex,configuredRecord in=$records do={
    :local configuredHostname [:pick $configuredRecord 0]
    :local configuredRecordId [:pick $configuredRecord 1]
    :local shouldUpdate false

    :if ([:tostr ($publicDNSIp->$recordIndex)] != [:tostr $publicIp]) do={
        :set shouldUpdate true
    }

    :if ($shouldUpdate = true) do={
        :onerror dnsUpdateError in={
            :local updateData ("{\"content\":\"" . $publicIp . "\"}")
            :local updateResponse [/tool fetch \
                url=($dnsCloudflareUrl . $configuredRecordId) \
                http-method=patch \
                http-header-field=$cloudflareHeaders \
                http-data=$updateData \
                output=user as-value]
            :if (($updateResponse->"code") != 200) do={
                :log error ("MikroTikDDNSUpdater: DNS PATCH failed for " . \
                    $configuredHostname . ": HTTP status " . ($updateResponse->"code"))
                :error ("HTTP status " . ($updateResponse->"code"))
            }
            :local updateJson [:deserialize from=json value=($updateResponse->"data")]

            :if (($updateJson->"success") != true) do={
                :log error ("MikroTikDDNSUpdater: Cloudflare rejected update for " . $configuredHostname)
                :error "MikroTikDDNSUpdater: DNS update was not successful"
            }

            :log info ("MikroTikDDNSUpdater: updated " . $configuredHostname . " to " . $publicIp)
        } do={
            :log error ("MikroTikDDNSUpdater: failed to update " . \
                $configuredHostname . ": " . $dnsUpdateError)
            :error "MikroTikDDNSUpdater: Cloudflare DNS update failed"
        }
    } else={
        :log info ("MikroTikDDNSUpdater: no update required for " . $configuredHostname)
    }
}