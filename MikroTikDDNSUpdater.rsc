#!rsc by RouterOS
# MikroTikDDNSUpdater
# Build: 17
#
# https://github.com/lolostt/MikroTikDDNSUpdater
# Copyright (C) 2026 Sleeping Coconut https://sleepingcoconut.com
# Licensed under the MIT License.
#
# Updates DuckDNS, No-IP, Dynu, FreeDNS and/or Cloudflare DNS records with the router's current public IPv4 address.
# Requires RouterOS 7.23.4 or newer.
#
# Usage:
#    1. Fill the "User configuration" block below.
#    2. Add the script under System > Scripts with "read" and "test" policies
#       (the only ones it needs). The scheduler entry needs the same policies.
#    3. Run it once with dryRun set to true and check the log.
#    4. Set dryRun to false and schedule it under System > Scheduler.

# ============================================================================
# User configuration
# ============================================================================

# Write every value between double quotes. Inside them, RouterOS reads $ as the start of a
# variable, " as the end of the value and \ as an escape, and changes the value without any
# error: write \$, \" and \\ instead (the password Pa$s"w\d goes as "Pa\$s\"w\\d").

# DNS records to keep updated. Field names and hostnames must be lowercase.
#   DuckDNS:    {provider="duckdns"; hostname="home.duckdns.org"}
#   No-IP:      {provider="noip"; hostname="home.ddns.net"}
#   Dynu:       {provider="dynu"; hostname="home.dynu.net"}
#   FreeDNS:    {provider="freedns"; hostname="home.mooo.com"; token="<update token>"}
#   Cloudflare: {provider="cloudflare"; hostname="home.example.com"; zoneid="<zone ID>"}
#
# Multi-WAN (only with publicIpService "interface"): every record takes the IP of wanInterface.
# To make one record follow another WAN, add interface="<name>" inside that record's own entry,
# next to provider and hostname:
#   {provider="noip"; hostname="office.ddns.net"; interface="ether2"}
# With any other publicIpService, a record with an interface field is an error.

:local records {
    {provider="duckdns"; hostname="SUBDOMAIN.DOMAIN.COM"};
    {provider="noip"; hostname="SUBDOMAIN.DOMAIN.COM"};
    {provider="dynu"; hostname="SUBDOMAIN.DOMAIN.COM"};
    {provider="freedns"; hostname="SUBDOMAIN.DOMAIN.COM"; token="FREEDNS_TOKEN"};
    {provider="cloudflare"; hostname="SUBDOMAIN.DOMAIN.COM"; zoneid="CLOUDFLARE_ZONE_ID"}
}

# ----- DuckDNS

# DuckDNS account token, shown on duckdns.org after signing in. Only needed for DuckDNS records.
:local duckdnsToken "DUCKDNS_TOKEN"

# ----- No-IP

# No-IP account. The username can be the account email. Only needed for No-IP records.
:local noipUsername "USER@DOMAIN.COM"
:local noipPassword "PASSWORD"

# ----- Dynu

# Dynu account username. As password, use the IP Update Password (Control Panel > My Account >
# Username/Password) or its MD5 or SHA-256 hash, not the account password: it only allows IP
# updates. Only needed for Dynu records.
:local dynuUsername "USERNAME"
:local dynuPassword "PASSWORD"

# ----- FreeDNS

# FreeDNS has no account data here: each record carries its own update token (token=...), the
# part after /u/ in its "Dynamic DNS" v2 update URL on freedns.afraid.org.

# ----- Cloudflare

# Cloudflare API token with Zone > DNS > Edit permission, limited to the zones of your records
# (Zone Resources > Include > Specific zone). Only needed for Cloudflare records.
:local cloudflareApiToken "CLOUDFLARE_API_TOKEN"

# ----------------------------------------------------------------------------

# true = check the configuration and read every record, but do not change any DNS record.
# Only the Cloudflare token is tested (it is needed to read the records): DuckDNS, No-IP, Dynu
# and FreeDNS credentials are first sent when a record needs an update.
:local dryRun true

# "auto" tries every public IP service in order until one answers.
# Set "icanhazip", "ipify", "amazon", "ipinfo" or "mikrotik" to use only that service.
# "mikrotik" reads /ip cloud and only works if IP Cloud DDNS is already enabled.
# "interface" reads the IPv4 address of router interfaces instead: wanInterface for every
# record, or the interface field of a record that has one (see records above).
:local publicIpService "auto"

# Only for publicIpService "interface": the interface that holds the public IPv4 address,
# e.g. "pppoe-out1". Every record without its own interface field uses it; if all records
# have one, it can keep its placeholder. With PPPoE, use the PPPoE interface, not the
# Ethernet port under it. A private or CGNAT address on the interface is reported as an error.
:local wanInterface "WAN_INTERFACE"

# TLS certificate check for HTTPS requests: "yes", "yes-without-crl" or "no".
# "no" is not recommended: credentials travel in these requests.
:local checkCertificate "yes-without-crl"

# ============================================================================
# Hardcoded values
# ============================================================================

:local logPrefix "MikroTikDDNSUpdater: "
# Same number as the Build line at the top.
:local buildNumber 17
# No-IP asks clients to identify themselves; fetch would send "RouterOS <version>". No commas:
# http-header-field uses them to separate headers.
:local userAgent ("MikroTikDDNSUpdater/" . $buildNumber . " github.com/lolostt/MikroTikDDNSUpdater")

# Public IP services, in the order used by "auto". None of these names has an IPv6 address, so
# they answer with the IPv4 one (fetch in 7.23.4 has no ip-type option to force it). An IPv6
# answer would be rejected below and the next service tried.
:local publicIpServiceOrder {"icanhazip"; "ipify"; "amazon"; "ipinfo"; "mikrotik"}
:local publicIpServiceUrls {
    icanhazip="https://ipv4.icanhazip.com";
    ipify="https://api.ipify.org";
    amazon="https://checkip.amazonaws.com";
    ipinfo="https://ipinfo.io/ip"
}

# Addresses that can never be the public IP (private, CGNAT, loopback, link-local,
# documentation, multicast, reserved and broadcast), as {network; netmask} pairs.
# 198.18.0.0/15 (network benchmarking) is accepted on purpose: test setups use it.
:local nonPublicRanges {
    {0.0.0.0; 255.0.0.0};
    {10.0.0.0; 255.0.0.0};
    {100.64.0.0; 255.192.0.0};
    {127.0.0.0; 255.0.0.0};
    {169.254.0.0; 255.255.0.0};
    {172.16.0.0; 255.240.0.0};
    {192.0.2.0; 255.255.255.0};
    {192.168.0.0; 255.255.0.0};
    {198.51.100.0; 255.255.255.0};
    {203.0.113.0; 255.255.255.0};
    {224.0.0.0; 240.0.0.0};
    {240.0.0.0; 240.0.0.0}
}

# Carrier-grade NAT range: the ISP shares one public IP among several customers.
:local cgnatNetwork 100.64.0.0
:local cgnatNetmask 255.192.0.0

# Link-local range: the interface got no address from the ISP (e.g. no DHCP answer).
:local linkLocalNetwork 169.254.0.0
:local linkLocalNetmask 255.255.0.0

# Longest part of a provider answer copied to the log (an error page can be several KB).
:local maxAnswerLength 100

:local cloudflareApiUrl "https://api.cloudflare.com/client/v4/zones/"

# No-IP update API and authoritative name server (avoids stale cached answers).
:local noipUpdateUrl "https://dynupdate.no-ip.com/nic/update"
:local noipNameServer "nf1.no-ip.com"
# No-IP answers that must be fixed by the user; No-IP may block clients that keep retrying.
:local noipFatalCodes {"nohost"; "badauth"; "badagent"; "!donator"; "abuse"}

# Dynu update API (dyndns2, like No-IP), a name server present in every Dynu domain, and the
# answers that must be fixed by the user.
:local dynuUpdateUrl "https://api.dynu.com/nic/update"
:local dynuNameServer "ns0.dynu.com"
:local dynuFatalCodes {"nohost"; "badauth"; "notfqdn"; "numhost"; "!donator"; "abuse"; "unknown"}

# FreeDNS v2 update API (the token goes in the path) and authoritative name server.
:local freednsUpdateUrl "https://sync.afraid.org/u/"
:local freednsNameServer "ns1.afraid.org"

# DuckDNS update API, authoritative name server and the suffix every DuckDNS hostname ends with.
:local duckdnsUpdateUrl "https://www.duckdns.org/update"
:local duckdnsNameServer "ns1.duckdns.org"
:local duckdnsSuffix ".duckdns.org"

# Placeholders used to detect unedited configuration.
:local placeholderHostname "SUBDOMAIN.DOMAIN.COM"
:local placeholderCloudflareApiToken "CLOUDFLARE_API_TOKEN"
:local placeholderCloudflareZoneId "CLOUDFLARE_ZONE_ID"
:local placeholderNoipUsername "USER@DOMAIN.COM"
:local placeholderNoipPassword "PASSWORD"
:local placeholderDuckdnsToken "DUCKDNS_TOKEN"
:local placeholderDynuUsername "USERNAME"
:local placeholderDynuPassword "PASSWORD"
:local placeholderFreednsToken "FREEDNS_TOKEN"
:local placeholderWanInterface "WAN_INTERFACE"

# Allowed characters for format checks.
:local hostnameChars "abcdefghijklmnopqrstuvwxyz0123456789.-"
:local hexChars "0123456789abcdef"
:local digitChars "0123456789"
:local alphanumericChars "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
:local tokenChars ($alphanumericChars . "-_")

# ============================================================================
# Runtime variables
# ============================================================================

:local recordCount 0
:local usesCloudflare false
:local usesNoip false
:local cloudflareHeaders ""
:local noipAuthHeader ""
:local noipNameServerIp ""
:local usesDuckdns false
:local duckdnsNameServerIp ""
:local usesDynu false
:local dynuAuthHeader ""
:local dynuNameServerIp ""
:local usesFreedns false
:local freednsNameServerIp ""
:local publicIp ""
# Per-record state, indexed like $records.
:local recordIds [:toarray ""]
:local recordInterfaces [:toarray ""]
:local recordIps [:toarray ""]
:local dnsIps [:toarray ""]
:local needsUpdate [:toarray ""]
:local recordFailed [:toarray ""]
:local failedCount 0
:local updatedCount 0

# ============================================================================
# Validate user configuration
# ============================================================================

:log info ($logPrefix . "INFO - starting")

:if ([:typeof $dryRun] != "bool") do={
    :log error ($logPrefix . "ERROR - dryRun must be true or false")
    :error ($logPrefix . "invalid dryRun")
}

:if (($publicIpService != "auto") && ($publicIpService != "interface") && \
    ([:typeof [:find $publicIpServiceOrder $publicIpService]] != "num")) do={
    :log error ($logPrefix . "ERROR - unknown publicIpService: " . $publicIpService)
    :error ($logPrefix . "invalid publicIpService")
}

:if (($checkCertificate != "yes") && ($checkCertificate != "yes-without-crl") && \
    ($checkCertificate != "no")) do={
    :log error ($logPrefix . "ERROR - checkCertificate must be yes, yes-without-crl or no")
    :error ($logPrefix . "invalid checkCertificate")
}
:if ($checkCertificate = "no") do={
    :log warning ($logPrefix . "WARNING - TLS certificates are not checked")
}

:if (([:typeof $records] != "array") || ([:len $records] = 0)) do={
    :log error ($logPrefix . "ERROR - records must contain at least one record")
    :error ($logPrefix . "records is empty")
}
:set recordCount [:len $records]

:foreach index,record in=$records do={
    :if ([:typeof $record] != "array") do={
        :log error ($logPrefix . "ERROR - record " . ($index + 1) . " is not a {...} entry")
        :error ($logPrefix . "invalid record")
    }

    # Only known fields. RouterOS reads an unquoted key with capitals (e.g. Hostname=) as a
    # comparison, which shows up here as a numbered entry instead of a named one.
    :foreach fieldName,fieldValue in=$record do={
        :if (([:typeof $fieldName] != "str") || (($fieldName != "provider") && \
            ($fieldName != "hostname") && ($fieldName != "zoneid") && \
            ($fieldName != "token") && ($fieldName != "interface"))) do={
            :log error ($logPrefix . "ERROR - record " . ($index + 1) . " has an unknown field" . \
                " (use provider, hostname, zoneid, token, interface in lowercase)")
            :error ($logPrefix . "invalid record field")
        }
    }

    :local provider ($record->"provider")
    :local hostname ($record->"hostname")

    :if (([:typeof $hostname] != "str") || ([:len $hostname] = 0) || \
        ($hostname = $placeholderHostname)) do={
        :log error ($logPrefix . "ERROR - hostname is not set in record " . ($index + 1))
        :error ($logPrefix . "hostname is not configured")
    }

    # Lowercase letters, digits, dots and hyphens only. The hostname goes into the provider URLs
    # as it is, so these checks are what keeps those URLs safe.
    :local labelLength 0
    :local longLabel false
    :for charIndex from=0 to=([:len $hostname] - 1) do={
        :local hostnameChar [:pick $hostname $charIndex]
        :if ([:typeof [:find $hostnameChars $hostnameChar]] != "num") do={
            :log error ($logPrefix . "ERROR - invalid hostname (lowercase only): " . $hostname)
            :error ($logPrefix . "invalid hostname")
        }
        :if ($hostnameChar = ".") do={
            :set labelLength 0
        } else={
            :set labelLength ($labelLength + 1)
            :if ($labelLength > 63) do={
                :set longLabel true
            }
        }
    }
    # At least two labels, none empty, none starting or ending with a hyphen, none longer than
    # 63 characters, and 253 characters in all.
    :local firstChar [:pick $hostname 0]
    :local lastChar [:pick $hostname ([:len $hostname] - 1)]
    :if (([:typeof [:find $hostname "."]] != "num") || \
        ([:typeof [:find $hostname ".."]] = "num") || \
        ([:typeof [:find $hostname ".-"]] = "num") || \
        ([:typeof [:find $hostname "-."]] = "num") || \
        ($firstChar = ".") || ($firstChar = "-") || ($lastChar = ".") || ($lastChar = "-") || \
        $longLabel || ([:len $hostname] > 253)) do={
        :log error ($logPrefix . "ERROR - hostname must be a full domain name: " . $hostname)
        :error ($logPrefix . "invalid hostname")
    }

    :foreach otherIndex,otherRecord in=$records do={
        :if (($otherIndex != $index) && (($otherRecord->"hostname") = $hostname)) do={
            :log error ($logPrefix . "ERROR - hostname is listed twice: " . $hostname)
            :error ($logPrefix . "duplicated hostname")
        }
    }

    # Interface mode: each record uses its own interface field, or wanInterface.
    :local recordInterface ""
    :if ([:typeof ($record->"interface")] != "nothing") do={
        :if ($publicIpService != "interface") do={
            :log error ($logPrefix . "ERROR - interface in " . $hostname . \
                " only works with publicIpService interface")
            :error ($logPrefix . "interface field without interface mode")
        }
        :set recordInterface ($record->"interface")
        :if (([:typeof $recordInterface] != "str") || ([:len $recordInterface] = 0)) do={
            :log error ($logPrefix . "ERROR - interface is empty in " . $hostname)
            :error ($logPrefix . "invalid interface")
        }
    } else={
        :if ($publicIpService = "interface") do={
            :if (([:len $wanInterface] = 0) || ($wanInterface = $placeholderWanInterface)) do={
                :log error ($logPrefix . "ERROR - wanInterface is not set (needed by " . \
                    $hostname . ")")
                :error ($logPrefix . "wanInterface is not configured")
            }
            :set recordInterface $wanInterface
        }
    }
    :if (([:len $recordInterface] > 0) && \
        ([:len [/interface find where name=$recordInterface]] = 0)) do={
        :log error ($logPrefix . "ERROR - interface not found: " . $recordInterface)
        :error ($logPrefix . "interface not found")
    }
    :set recordInterfaces ($recordInterfaces, $recordInterface)

    :if ($provider = "cloudflare") do={
        :set usesCloudflare true
        :local zoneId ($record->"zoneid")
        :if (([:typeof $zoneId] != "str") || ($zoneId = $placeholderCloudflareZoneId)) do={
            :log error ($logPrefix . "ERROR - zoneid is not set for " . $hostname)
            :error ($logPrefix . "zoneid is not configured")
        }
        # Cloudflare zone IDs are 32 lowercase hex characters.
        :if ([:len $zoneId] != 32) do={
            :log error ($logPrefix . "ERROR - zoneid must have 32 characters for " . $hostname)
            :error ($logPrefix . "invalid zoneid")
        }
        :for charIndex from=0 to=31 do={
            :if ([:typeof [:find $hexChars [:pick $zoneId $charIndex]]] != "num") do={
                :log error ($logPrefix . "ERROR - zoneid must be lowercase hex for " . $hostname)
                :error ($logPrefix . "invalid zoneid")
            }
        }
    } else={
        :if ($provider = "noip") do={
            :set usesNoip true
        } else={
            :if ($provider = "duckdns") do={
                :set usesDuckdns true
                # DuckDNS only updates names directly under duckdns.org; deeper names
                # (a.home.duckdns.org) follow the IP of their parent.
                :local suffixStart ([:len $hostname] - [:len $duckdnsSuffix])
                :if (($suffixStart < 1) || \
                    ([:pick $hostname $suffixStart [:len $hostname]] != $duckdnsSuffix) || \
                    ([:typeof [:find [:pick $hostname 0 $suffixStart] "."]] = "num")) do={
                    :log error ($logPrefix . "ERROR - DuckDNS hostname must be <name>" . \
                        $duckdnsSuffix . ": " . $hostname)
                    :error ($logPrefix . "invalid DuckDNS hostname")
                }
            } else={
                :if ($provider = "dynu") do={
                    :set usesDynu true
                } else={
                    :if ($provider = "freedns") do={
                        :set usesFreedns true
                        :local token ($record->"token")
                        :if (([:typeof $token] != "str") || ([:len $token] = 0) || \
                            ($token = $placeholderFreednsToken)) do={
                            :log error ($logPrefix . "ERROR - token is not set for " . $hostname)
                            :error ($logPrefix . "FreeDNS token is not configured")
                        }
                        # The token goes in the URL path: letters and digits only.
                        :for charIndex from=0 to=([:len $token] - 1) do={
                            :if ([:typeof [:find $alphanumericChars [:pick $token $charIndex]]] != "num") do={
                                :log error ($logPrefix . "ERROR - token must be letters and digits only for " . \
                                    $hostname)
                                :error ($logPrefix . "invalid FreeDNS token")
                            }
                        }
                    } else={
                        :log error ($logPrefix . "ERROR - unknown provider for " . $hostname . \
                            " (use duckdns, noip, dynu, freedns or cloudflare)")
                        :error ($logPrefix . "invalid provider")
                    }
                }
            }
        }
    }

    # A field of another provider would be ignored without notice (e.g. a token in a DuckDNS
    # record, whose token is duckdnsToken).
    :if (([:typeof ($record->"zoneid")] != "nothing") && ($provider != "cloudflare")) do={
        :log error ($logPrefix . "ERROR - zoneid only goes in Cloudflare records: " . $hostname)
        :error ($logPrefix . "zoneid in a record of another provider")
    }
    :if (([:typeof ($record->"token")] != "nothing") && ($provider != "freedns")) do={
        :log error ($logPrefix . "ERROR - token only goes in FreeDNS records: " . $hostname)
        :error ($logPrefix . "token in a record of another provider")
    }
}

# Credentials are only required for the providers in use.
:if ($usesCloudflare) do={
    :if (([:len $cloudflareApiToken] = 0) || \
        ($cloudflareApiToken = $placeholderCloudflareApiToken)) do={
        :log error ($logPrefix . "ERROR - Cloudflare API token is not set")
        :error ($logPrefix . "Cloudflare API token is not configured")
    }
    # The token goes in an HTTP header: letters, digits, hyphens and underscores only.
    :for charIndex from=0 to=([:len $cloudflareApiToken] - 1) do={
        :if ([:typeof [:find $tokenChars [:pick $cloudflareApiToken $charIndex]]] != "num") do={
            :log error ($logPrefix . "ERROR - Cloudflare API token must be letters, digits, - and _ only")
            :error ($logPrefix . "invalid Cloudflare API token")
        }
    }
    # http-header-field format: "name:value,name:value".
    :set cloudflareHeaders ("Authorization:Bearer " . $cloudflareApiToken . \
        ",Content-Type:application/json")
}

:if ($usesNoip) do={
    :if (([:len $noipUsername] = 0) || ($noipUsername = $placeholderNoipUsername)) do={
        :log error ($logPrefix . "ERROR - No-IP username is not set")
        :error ($logPrefix . "No-IP username is not configured")
    }
    # A colon would break the "username:password" pair of HTTP Basic authentication.
    :if ([:typeof [:find $noipUsername ":"]] = "num") do={
        :log error ($logPrefix . "ERROR - No-IP username must not contain a colon")
        :error ($logPrefix . "invalid No-IP username")
    }
    :if (([:len $noipPassword] = 0) || ($noipPassword = $placeholderNoipPassword)) do={
        :log error ($logPrefix . "ERROR - No-IP password is not set")
        :error ($logPrefix . "No-IP password is not configured")
    }
    :set noipAuthHeader ("Basic " . [:convert ($noipUsername . ":" . $noipPassword) \
        from=raw to=base64])
}

:if ($usesDynu) do={
    :if (([:len $dynuUsername] = 0) || ($dynuUsername = $placeholderDynuUsername)) do={
        :log error ($logPrefix . "ERROR - Dynu username is not set")
        :error ($logPrefix . "Dynu username is not configured")
    }
    # A colon would break the "username:password" pair of HTTP Basic authentication.
    :if ([:typeof [:find $dynuUsername ":"]] = "num") do={
        :log error ($logPrefix . "ERROR - Dynu username must not contain a colon")
        :error ($logPrefix . "invalid Dynu username")
    }
    :if (([:len $dynuPassword] = 0) || ($dynuPassword = $placeholderDynuPassword)) do={
        :log error ($logPrefix . "ERROR - Dynu password is not set")
        :error ($logPrefix . "Dynu password is not configured")
    }
    :set dynuAuthHeader ("Basic " . [:convert ($dynuUsername . ":" . $dynuPassword) \
        from=raw to=base64])
}

:if ($usesDuckdns) do={
    :if (([:len $duckdnsToken] = 0) || ($duckdnsToken = $placeholderDuckdnsToken)) do={
        :log error ($logPrefix . "ERROR - DuckDNS token is not set")
        :error ($logPrefix . "DuckDNS token is not configured")
    }
    # DuckDNS tokens are UUIDs: 36 lowercase hex characters with hyphens at 8, 13, 18 and 23.
    :local tokenOk ([:len $duckdnsToken] = 36)
    :if ($tokenOk) do={
        :for charIndex from=0 to=35 do={
            :local tokenChar [:pick $duckdnsToken $charIndex]
            :if (($charIndex = 8) || ($charIndex = 13) || ($charIndex = 18) || ($charIndex = 23)) do={
                :if ($tokenChar != "-") do={
                    :set tokenOk false
                }
            } else={
                :if ([:typeof [:find $hexChars $tokenChar]] != "num") do={
                    :set tokenOk false
                }
            }
        }
    }
    :if ($tokenOk = false) do={
        :log error ($logPrefix . "ERROR - DuckDNS token must look like" . \
            " xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx (lowercase hex)")
        :error ($logPrefix . "invalid DuckDNS token")
    }
}

:log info ($logPrefix . "INFO - configuration OK, " . $recordCount . " records")
:if ($dryRun) do={
    :log warning ($logPrefix . "WARNING - dry-run enabled, DNS records will not be changed")
}

# ============================================================================
# Get the router's public IP address
# ============================================================================

:foreach serviceName in=$publicIpServiceOrder do={
    # Use only the selected service, and skip the rest once one has answered.
    :if ((($publicIpService = "auto") || ($publicIpService = $serviceName)) && \
        ([:typeof $publicIp] != "ip")) do={
        :local answer ""
        :local lookupOk true

        :onerror lookupError in={
            :if ($serviceName = "mikrotik") do={
                :set answer [:tostr [/ip cloud get public-address]]
            } else={
                :local response [/tool fetch url=($publicIpServiceUrls->$serviceName) \
                    check-certificate=$checkCertificate output=user as-value]
                :set answer [:tostr ($response->"data")]
            }
        } do={
            :set lookupOk false
            :log warning ($logPrefix . "WARNING - " . $serviceName . " failed: " . $lookupError)
        }

        :if ($lookupOk) do={
            # Keep only the first line, without line endings or trailing spaces.
            :local lineEnd [:find $answer "\n"]
            :if ([:typeof $lineEnd] = "num") do={
                :set answer [:pick $answer 0 $lineEnd]
            }
            :set lineEnd [:find $answer "\r"]
            :if ([:typeof $lineEnd] = "num") do={
                :set answer [:pick $answer 0 $lineEnd]
            }
            :set lineEnd [:find $answer " "]
            :if ([:typeof $lineEnd] = "num") do={
                :set answer [:pick $answer 0 $lineEnd]
            }

            # Accept only four dot-separated numbers from 0 to 255, so that partial values
            # such as "10.1" (which :toip would expand) are rejected.
            :local formatOk (([:len $answer] >= 7) && ([:len $answer] <= 15))
            :if ($formatOk) do={
                :local octetCount 0
                :local octetText ""
                # Loop one step past the end, read as ".", to close the last octet.
                :for charIndex from=0 to=[:len $answer] do={
                    :local currentChar "."
                    :if ($charIndex < [:len $answer]) do={
                        :set currentChar [:pick $answer $charIndex]
                    }
                    :if ($currentChar = ".") do={
                        :if (([:len $octetText] = 0) || ([:len $octetText] > 3)) do={
                            :set formatOk false
                        } else={
                            :if ([:tonum $octetText] > 255) do={
                                :set formatOk false
                            }
                        }
                        :set octetCount ($octetCount + 1)
                        :set octetText ""
                    } else={
                        :if ([:typeof [:find $digitChars $currentChar]] = "num") do={
                            :set octetText ($octetText . $currentChar)
                        } else={
                            :set formatOk false
                        }
                    }
                }
                :if ($octetCount != 4) do={
                    :set formatOk false
                }
            }

            :local candidateIp ""
            :if ($formatOk) do={
                :set candidateIp [:toip $answer]
            }
            :if ([:typeof $candidateIp] = "ip") do={
                :local isPublic true
                :foreach range in=$nonPublicRanges do={
                    :if (($candidateIp & ($range->1)) = ($range->0)) do={
                        :set isPublic false
                    }
                }
                :if ($isPublic) do={
                    :set publicIp $candidateIp
                    :log info ($logPrefix . "INFO - public IP is " . $publicIp . \
                        " (" . $serviceName . ")")
                } else={
                    :log warning ($logPrefix . "WARNING - " . $serviceName . \
                        " returned a non-public address: " . $candidateIp)
                }
            } else={
                :log warning ($logPrefix . "WARNING - " . $serviceName . \
                    " did not return a valid IPv4 address")
            }
        }
    }
}

:if (($publicIpService != "interface") && ([:typeof $publicIp] != "ip")) do={
    :log error ($logPrefix . "ERROR - unable to get the public IP from any service")
    :error ($logPrefix . "unable to get the public IP")
}

# Every record gets the same public IP, unless interface mode sets each one below.
:for index from=0 to=($recordCount - 1) do={
    :set recordIds ($recordIds, "")
    :set recordIps ($recordIps, $publicIp)
    :set dnsIps ($dnsIps, "")
    :set needsUpdate ($needsUpdate, false)
    :set recordFailed ($recordFailed, false)
}

# Interface mode: read the address of each record's interface (several WANs are allowed).
:if ($publicIpService = "interface") do={
    :foreach index,record in=$records do={
        :local hostname ($record->"hostname")
        :local interfaceName ($recordInterfaces->$index)
        :local interfaceIp ""
        :local alreadyRead false

        # Reuse the result of an earlier record on the same interface.
        :foreach otherIndex,otherInterface in=$recordInterfaces do={
            :if (($otherIndex < $index) && ($otherInterface = $interfaceName) && \
                ($alreadyRead = false)) do={
                :set alreadyRead true
                :set interfaceIp ($recordIps->$otherIndex)
            }
        }

        :if ($alreadyRead = false) do={
            :onerror interfaceError in={
                :local addressIds [/ip address find where interface=$interfaceName \
                    disabled=no invalid=no]
                :if ([:len $addressIds] = 0) do={
                    :error "no IPv4 address on the interface"
                }
                # Use the first public address: the interface may also hold a private one, e.g.
                # to reach the modem. Without any, keep the first one for the checks below.
                :local publicCount 0
                :foreach addressId in=$addressIds do={
                    # The address comes with its prefix length ("198.18.0.5/32").
                    :local address [:tostr [/ip address get $addressId address]]
                    :local candidateIp [:toip [:pick $address 0 [:find $address "/"]]]
                    :local isPublic true
                    :foreach range in=$nonPublicRanges do={
                        :if (($candidateIp & ($range->1)) = ($range->0)) do={
                            :set isPublic false
                        }
                    }
                    :if ($isPublic) do={
                        :set publicCount ($publicCount + 1)
                        :if ($publicCount = 1) do={
                            :set interfaceIp $candidateIp
                        }
                    }
                    :if ([:typeof $interfaceIp] != "ip") do={
                        :set interfaceIp $candidateIp
                    }
                }
                :if ($publicCount > 1) do={
                    :log warning ($logPrefix . "WARNING - " . $interfaceName . \
                        " has several public IPv4 addresses, using the first one")
                }
            } do={
                :log error ($logPrefix . "ERROR - cannot read the IPv4 address of " . \
                    $interfaceName . ": " . $interfaceError)
            }

            # Active PPPoE clients on this interface, directly or through a VLAN: the public IP
            # is on the PPPoE interface, so wanInterface (or interface) points to the wrong one.
            :local pppoeNames ""
            :local pppoeIds [/interface pppoe-client find where interface=$interfaceName disabled=no]
            :foreach vlanId in=[/interface vlan find where interface=$interfaceName] do={
                :local vlanName [/interface vlan get $vlanId name]
                :set pppoeIds ($pppoeIds, [/interface pppoe-client find where interface=$vlanName \
                    disabled=no])
            }
            :foreach pppoeId in=$pppoeIds do={
                :if ([:len $pppoeNames] > 0) do={
                    :set pppoeNames ($pppoeNames . ", ")
                }
                :set pppoeNames ($pppoeNames . [/interface pppoe-client get $pppoeId name])
            }

            :if ([:typeof $interfaceIp] = "ip") do={
                :local isPublic true
                :foreach range in=$nonPublicRanges do={
                    :if (($interfaceIp & ($range->1)) = ($range->0)) do={
                        :set isPublic false
                    }
                }
                :if ($isPublic) do={
                    :log info ($logPrefix . "INFO - public IP is " . $interfaceIp . \
                        " (" . $interfaceName . ")")
                } else={
                    :if (($interfaceIp & $cgnatNetmask) = $cgnatNetwork) do={
                        :log error ($logPrefix . "ERROR - " . $interfaceName . " has " . \
                            $interfaceIp . ", a CGNAT address: the ISP shares the public IP and" . \
                            " the router cannot be reached from the Internet")
                    } else={
                        :if (($interfaceIp & $linkLocalNetmask) = $linkLocalNetwork) do={
                            :log error ($logPrefix . "ERROR - " . $interfaceName . " has the link-local" . \
                                " address " . $interfaceIp . ": it got no address from the ISP")
                        } else={
                            # With a PPPoE client on top, the private address is not a sign of NAT.
                            :if ([:len $pppoeNames] = 0) do={
                                :log error ($logPrefix . "ERROR - " . $interfaceName . " has the" . \
                                    " private address " . $interfaceIp . ": the router is behind" . \
                                    " another NAT device, use publicIpService auto")
                            }
                        }
                    }
                    :set interfaceIp ""
                }
            }

            :if (([:typeof $interfaceIp] != "ip") && ([:len $pppoeNames] > 0)) do={
                :log error ($logPrefix . "ERROR - " . $interfaceName . " carries the PPPoE client " . \
                    $pppoeNames . ": set wanInterface (or interface) to " . $pppoeNames)
            }
        }

        :set ($recordIps->$index) $interfaceIp
        :if ([:typeof $interfaceIp] != "ip") do={
            :set ($recordFailed->$index) true
            :set failedCount ($failedCount + 1)
            :log error ($logPrefix . "ERROR - " . $hostname . " skipped: no public IP on " . \
                $interfaceName)
        }
    }
}

# ============================================================================
# Get the current IP address of each DNS record
# ============================================================================

# Ask each provider's own name server; fall back to the router's resolver if it cannot be found.
:if ($usesNoip) do={
    :onerror nameServerError in={
        :set noipNameServerIp [:resolve domain-name=$noipNameServer type=ipv4]
    } do={
        :log warning ($logPrefix . "WARNING - cannot resolve " . $noipNameServer . \
            ", using the router's DNS for No-IP records")
    }
}
:if ($usesDuckdns) do={
    :onerror nameServerError in={
        :set duckdnsNameServerIp [:resolve domain-name=$duckdnsNameServer type=ipv4]
    } do={
        :log warning ($logPrefix . "WARNING - cannot resolve " . $duckdnsNameServer . \
            ", using the router's DNS for DuckDNS records")
    }
}
:if ($usesDynu) do={
    :onerror nameServerError in={
        :set dynuNameServerIp [:resolve domain-name=$dynuNameServer type=ipv4]
    } do={
        :log warning ($logPrefix . "WARNING - cannot resolve " . $dynuNameServer . \
            ", using the router's DNS for Dynu records")
    }
}
:if ($usesFreedns) do={
    :onerror nameServerError in={
        :set freednsNameServerIp [:resolve domain-name=$freednsNameServer type=ipv4]
    } do={
        :log warning ($logPrefix . "WARNING - cannot resolve " . $freednsNameServer . \
            ", using the router's DNS for FreeDNS records")
    }
}

:foreach index,record in=$records do={
    :local provider ($record->"provider")
    :local hostname ($record->"hostname")

    # Records already skipped for lack of a public IP are not looked up.
    :if (($recordFailed->$index) = false) do={
        :onerror readError,readErrorInfo in={
            :if ($provider = "cloudflare") do={
                # Look the A record up by name so its ID does not need to be configured.
                :local response [/tool fetch \
                    url=($cloudflareApiUrl . ($record->"zoneid") . "/dns_records?type=A&name=" . $hostname) \
                    http-method=get http-header-field=$cloudflareHeaders \
                    check-certificate=$checkCertificate output=user as-value]
                # Keep JSON strings as strings; record IDs must not be turned into numbers.
                :local responseJson [:deserialize from=json options=json.no-string-conversion \
                    value=($response->"data")]
                :if (($responseJson->"success") != true) do={
                    :error "Cloudflare answered success=false"
                }
                :local matches ($responseJson->"result")
                :if ([:len $matches] = 0) do={
                    :error "no A record with this name in the zone"
                }
                :if ([:len $matches] > 1) do={
                    :error "more than one A record with this name"
                }
                :set ($recordIds->$index) [:tostr (($matches->0)->"id")]
                :set ($dnsIps->$index) [:toip (($matches->0)->"content")]
            }
            :if ($provider != "cloudflare") do={
                :local nameServerIp $noipNameServerIp
                :if ($provider = "duckdns") do={
                    :set nameServerIp $duckdnsNameServerIp
                }
                :if ($provider = "dynu") do={
                    :set nameServerIp $dynuNameServerIp
                }
                :if ($provider = "freedns") do={
                    :set nameServerIp $freednsNameServerIp
                }
                :if ([:typeof $nameServerIp] = "ip") do={
                    # If the provider's server does not answer, the API may still work: read the
                    # record through the router's DNS so that the update is not blocked.
                    :onerror nameServerError in={
                        :set ($dnsIps->$index) [:resolve domain-name=$hostname \
                            server=$nameServerIp type=ipv4]
                    } do={
                        :log warning ($logPrefix . "WARNING - the name server of " . $hostname . \
                            " failed (" . $nameServerError . "), using the router's DNS," . \
                            " which may still hold the old IP")
                        :set ($dnsIps->$index) [:resolve domain-name=$hostname type=ipv4]
                    }
                } else={
                    :set ($dnsIps->$index) [:resolve domain-name=$hostname type=ipv4]
                }
            }

            :if ([:typeof ($dnsIps->$index)] != "ip") do={
                :error "the record does not hold an IPv4 address"
            }
            :log info ($logPrefix . "INFO - " . $hostname . " points to " . ($dnsIps->$index))
        } do={
            :set ($recordFailed->$index) true
            :set failedCount ($failedCount + 1)
            :log error ($logPrefix . "ERROR - cannot read " . $hostname . ": " . $readError)
            # fetch reports Cloudflare 401/403 with a cryptic message: add a clearer hint.
            :local httpStatus [:tonum ($readErrorInfo->"code")]
            # A 401 without WWW-Authenticate header is reported as a parsing error, with no code.
            :if ([:typeof [:find $readError "http: 401 "]] = "num") do={
                :set httpStatus 401
            }
            :if (($provider = "cloudflare") && (($httpStatus = 401) || ($httpStatus = 403))) do={
                :log error ($logPrefix . "ERROR - check that the Cloudflare API token is valid" . \
                    " and can read DNS records of the zone of " . $hostname)
            }
        }
    }
}

# ============================================================================
# Compare the public IP with each DNS record
# ============================================================================

:foreach index,record in=$records do={
    :local hostname ($record->"hostname")
    :local recordIp ($recordIps->$index)

    :if (($recordFailed->$index) = false) do={
        :if ([:tostr ($dnsIps->$index)] = [:tostr $recordIp]) do={
            :log info ($logPrefix . "INFO - " . $hostname . " is up to date")
        } else={
            :set ($needsUpdate->$index) true
            :log info ($logPrefix . "INFO - " . $hostname . " needs update: " . \
                ($dnsIps->$index) . " -> " . $recordIp)
        }
    }
}

# ============================================================================
# Update the DNS records that need it
# ============================================================================

:foreach index,record in=$records do={
    :local provider ($record->"provider")
    :local hostname ($record->"hostname")
    :local recordIp ($recordIps->$index)

    :if (($needsUpdate->$index) = true) do={
        :if ($dryRun) do={
            :log warning ($logPrefix . "WARNING - dry-run, " . $hostname . " not updated to " . $recordIp)
        } else={
            :local dyndnsFatal false
            :local dyndnsBadauth false
            :local duckdnsRejected false
            :local freednsRejected false
            # Cleared when the provider answers that the record already had this IP.
            :local recordChanged true
            # No-IP and Dynu share the dyndns2 protocol; only the URL, account and codes differ.
            :local dyndnsName "No-IP"
            :local dyndnsUrl $noipUpdateUrl
            :local dyndnsAuthHeader $noipAuthHeader
            :local dyndnsFatalCodes $noipFatalCodes
            :if ($provider = "dynu") do={
                :set dyndnsName "Dynu"
                :set dyndnsUrl $dynuUpdateUrl
                :set dyndnsAuthHeader $dynuAuthHeader
                :set dyndnsFatalCodes $dynuFatalCodes
            }
            :onerror updateError,updateErrorInfo in={
                :if ($provider = "cloudflare") do={
                    # Only the content is sent, so proxy status and TTL are kept.
                    :local response [/tool fetch \
                        url=($cloudflareApiUrl . ($record->"zoneid") . "/dns_records/" . ($recordIds->$index)) \
                        http-method=patch http-header-field=$cloudflareHeaders \
                        http-data=("{\"content\":\"" . $recordIp . "\"}") \
                        check-certificate=$checkCertificate output=user as-value]
                    :local responseJson [:deserialize from=json options=json.no-string-conversion \
                        value=($response->"data")]
                    :if (($responseJson->"success") != true) do={
                        :error "Cloudflare answered success=false"
                    }
                    :log info ($logPrefix . "INFO - " . $hostname . " updated to " . $recordIp)
                }
                :if (($provider = "noip") || ($provider = "dynu")) do={
                    :local response [/tool fetch \
                        url=($dyndnsUrl . "?hostname=" . $hostname . "&myip=" . $recordIp) \
                        http-header-field=("Authorization:" . $dyndnsAuthHeader . ",User-Agent:" . \
                            $userAgent) \
                        check-certificate=$checkCertificate output=user as-value]

                    # The answer is a code, optionally followed by the IP ("good 1.2.3.4").
                    :local answerLine [:tostr ($response->"data")]
                    :local cutAt [:find $answerLine "\n"]
                    :if ([:typeof $cutAt] = "num") do={
                        :set answerLine [:pick $answerLine 0 $cutAt]
                    }
                    :set cutAt [:find $answerLine "\r"]
                    :if ([:typeof $cutAt] = "num") do={
                        :set answerLine [:pick $answerLine 0 $cutAt]
                    }
                    :set answerLine [:pick $answerLine 0 $maxAnswerLength]
                    :local answerCode $answerLine
                    :local answerIp ""
                    :set cutAt [:find $answerLine " "]
                    :if ([:typeof $cutAt] = "num") do={
                        :set answerCode [:pick $answerLine 0 $cutAt]
                        :set answerIp [:pick $answerLine ($cutAt + 1) [:len $answerLine]]
                    }

                    # "good" = updated, "nochg" = already had this IP. Anything else is an error.
                    :if (($answerCode != "good") && ($answerCode != "nochg")) do={
                        :if ([:typeof [:find $dyndnsFatalCodes $answerCode]] = "num") do={
                            :set dyndnsFatal true
                        }
                        :if ($answerCode = "badauth") do={
                            :set dyndnsBadauth true
                        }
                        :error ($dyndnsName . " answered " . $answerLine)
                    }
                    :if ($answerCode = "good") do={
                        :log info ($logPrefix . "INFO - " . $hostname . " updated to " . $recordIp . \
                            " (" . $dyndnsName . ": " . $answerLine . ")")
                    } else={
                        :set recordChanged false
                        :log info ($logPrefix . "INFO - " . $hostname . " already had " . $recordIp . \
                            " (" . $dyndnsName . ": " . $answerLine . ")")
                    }
                    # Dynu may answer the code alone; No-IP always adds the IP.
                    :if (($answerIp != [:tostr $recordIp]) && \
                        (($provider = "noip") || ([:len $answerIp] > 0))) do={
                        :log warning ($logPrefix . "WARNING - " . $dyndnsName . " did not keep " . \
                            $recordIp . " for " . $hostname)
                    }
                }
                :if ($provider = "freedns") do={
                    :local response [/tool fetch \
                        url=($freednsUpdateUrl . ($record->"token") . "/?hostname=" . $hostname . \
                            "&myip=" . $recordIp) \
                        check-certificate=$checkCertificate output=user as-value]

                    # One line of text, e.g. "Updated 1 host(s) ..." or "No IP change detected ...".
                    :local answerLine [:tostr ($response->"data")]
                    :local cutAt [:find $answerLine "\n"]
                    :if ([:typeof $cutAt] = "num") do={
                        :set answerLine [:pick $answerLine 0 $cutAt]
                    }
                    :set cutAt [:find $answerLine "\r"]
                    :if ([:typeof $cutAt] = "num") do={
                        :set answerLine [:pick $answerLine 0 $cutAt]
                    }
                    :set answerLine [:pick $answerLine 0 $maxAnswerLength]
                    :if ([:find $answerLine "Updated"] = 0) do={
                        :log info ($logPrefix . "INFO - " . $hostname . " updated to " . $recordIp . \
                            " (FreeDNS: " . $answerLine . ")")
                    } else={
                        :if ([:find $answerLine "No IP change detected"] = 0) do={
                            :set recordChanged false
                            :log info ($logPrefix . "INFO - " . $hostname . " already had " . $recordIp . \
                                " (FreeDNS: " . $answerLine . ")")
                        } else={
                            :if ([:typeof [:find $answerLine "find any matching DNS records"]] = "num") do={
                                :set freednsRejected true
                            }
                            :error ("FreeDNS answered " . $answerLine)
                        }
                    }
                }
                :if ($provider = "duckdns") do={
                    # DuckDNS wants the name without .duckdns.org. One request per record keeps
                    # each failure tied to its own hostname.
                    :local subdomain [:pick $hostname 0 ([:len $hostname] - [:len $duckdnsSuffix])]
                    :local response [/tool fetch \
                        url=($duckdnsUpdateUrl . "?domains=" . $subdomain . "&token=" . $duckdnsToken . \
                            "&ip=" . $recordIp . "&verbose=true") \
                        check-certificate=$checkCertificate output=user as-value]

                    # Verbose answer, one item per line: OK or KO, IPv4, IPv6, UPDATED or NOCHANGE.
                    :local answer [:tostr ($response->"data")]
                    :local answerLines [:toarray ""]
                    :local lineText ""
                    # Loop one step past the end, read as a line break, to close the last line.
                    :for charIndex from=0 to=[:len $answer] do={
                        :local currentChar "\n"
                        :if ($charIndex < [:len $answer]) do={
                            :set currentChar [:pick $answer $charIndex]
                        }
                        :if ($currentChar = "\n") do={
                            :set answerLines ($answerLines, $lineText)
                            :set lineText ""
                        } else={
                            :if ($currentChar != "\r") do={
                                :set lineText ($lineText . $currentChar)
                            }
                        }
                    }
                    :local answerStatus [:pick [:tostr ($answerLines->0)] 0 $maxAnswerLength]
                    :local answerIp [:tostr ($answerLines->1)]
                    :local answerChange [:tostr ($answerLines->3)]

                    :if ($answerStatus = "KO") do={
                        :set duckdnsRejected true
                        :error "DuckDNS answered KO"
                    }
                    :if ($answerStatus != "OK") do={
                        :error ("DuckDNS answered " . $answerStatus)
                    }
                    # Without UPDATED or NOCHANGE the answer is not the verbose one: do not
                    # count it as updated.
                    :if (($answerChange != "UPDATED") && ($answerChange != "NOCHANGE")) do={
                        :error "DuckDNS answered OK without UPDATED or NOCHANGE"
                    }
                    :if ($answerChange = "NOCHANGE") do={
                        :set recordChanged false
                        :log info ($logPrefix . "INFO - " . $hostname . " already had " . $recordIp . \
                            " (DuckDNS: OK " . $answerChange . ")")
                    } else={
                        :log info ($logPrefix . "INFO - " . $hostname . " updated to " . $recordIp . \
                            " (DuckDNS: OK " . $answerChange . ")")
                    }
                    :if ($answerIp != [:tostr $recordIp]) do={
                        :log warning ($logPrefix . "WARNING - DuckDNS did not keep " . $recordIp . \
                            " for " . $hostname)
                    }
                }
                :if ($recordChanged) do={
                    :set updatedCount ($updatedCount + 1)
                }
            } do={
                :set failedCount ($failedCount + 1)
                # DuckDNS and FreeDNS tokens travel in the URL; never copy them to the log if
                # fetch or the answer quotes them.
                :local errorText [:tostr $updateError]
                :local secrets [:toarray ""]
                :if ($usesDuckdns) do={
                    :set secrets ($secrets, $duckdnsToken)
                }
                :if ($provider = "freedns") do={
                    :set secrets ($secrets, ($record->"token"))
                }
                :foreach secret in=$secrets do={
                    :local tokenAt [:find $errorText $secret]
                    :while ([:typeof $tokenAt] = "num") do={
                        :set errorText ([:pick $errorText 0 $tokenAt] . "<token>" . \
                            [:pick $errorText ($tokenAt + [:len $secret]) [:len $errorText]])
                        :set tokenAt [:find $errorText $secret]
                    }
                }
                :log error ($logPrefix . "ERROR - cannot update " . $hostname . ": " . $errorText)
                # 401/403 make fetch fail before any answer can be read: add a provider hint.
                # fetch gives the HTTP status as code; a 401 without WWW-Authenticate header is
                # reported as a parsing error, with no code.
                :local httpStatus [:tonum ($updateErrorInfo->"code")]
                :if ([:typeof [:find $errorText "http: 401 "]] = "num") do={
                    :set httpStatus 401
                }
                :local authError (($httpStatus = 401) || ($httpStatus = 403))
                :if (($provider = "cloudflare") && $authError) do={
                    :log error ($logPrefix . "ERROR - check that the Cloudflare API token can edit" . \
                        " DNS records of the zone of " . $hostname)
                }
                :if (($provider = "noip") && ($dyndnsFatal || $authError)) do={
                    :log error ($logPrefix . "ERROR - fix the No-IP account or hostname now:" . \
                        " No-IP may block clients that keep sending failing updates")
                }
                :if (($provider = "duckdns") && ($duckdnsRejected || $authError)) do={
                    :log error ($logPrefix . "ERROR - check the DuckDNS token and that " . $hostname . \
                        " belongs to the account")
                }
                :if (($provider = "dynu") && ($dyndnsFatal || $authError)) do={
                    :log error ($logPrefix . "ERROR - fix the Dynu account or hostname now:" . \
                        " Dynu may block clients that keep sending failing updates")
                }
                :if ($dyndnsBadauth) do={
                    :log error ($logPrefix . "ERROR - if the password has \$, \" or \\, write them" . \
                        " as \\\$, \\\" and \\\\ in the script")
                }
                # FreeDNS answers 404 to tokens that are not v2 ones (such as the longer v1 token).
                :if (($provider = "freedns") && ($freednsRejected || $authError || \
                    ($httpStatus = 404))) do={
                    :log error ($logPrefix . "ERROR - check that the token of " . $hostname . \
                        " is its FreeDNS v2 update token (the part after /u/), not the v1 one")
                }
            }
        }
    }
}

:if ($failedCount > 0) do={
    :log error ($logPrefix . "ERROR - finished with " . $failedCount . " failed records out of " . \
        $recordCount)
    :error ($logPrefix . "some records failed")
}
:if ($dryRun) do={
    :log info ($logPrefix . "INFO - finished (dry-run), no record was changed")
} else={
    :log info ($logPrefix . "INFO - finished, " . $updatedCount . " records updated")
}
