#!rsc by RouterOS
# MikrotikDDNSUpdater
# Build: 12
#
# https://github.com/lolostt/MikrotikDDNSUpdater
# Copyright (C) 2026 Sleeping Coconut https://sleepingcoconut.com
#
# Updates Cloudflare and/or No-IP DNS records with the router's current public IPv4 address.
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

# DNS records to keep updated. Field names and hostnames must be lowercase.
#   Cloudflare: {provider="cloudflare"; hostname="home.example.com"; zoneid="<zone ID>"}
#   No-IP:      {provider="noip"; hostname="home.ddns.net"}
:local records {
    {provider="cloudflare"; hostname="SUBDOMAIN.DOMAIN.COM"; zoneid="CLOUDFLARE_ZONE_ID"};
    {provider="noip"; hostname="SUBDOMAIN.DOMAIN.COM"}
}

# No-IP account. The username can be the account email. Only needed for No-IP records.
:local noipUsername "USER@DOMAIN.COM"
:local noipPassword "PASSWORD"

# ----------------------------------------------------------------------------

# Cloudflare API token with Zone > DNS > Edit permission. Only needed for Cloudflare records.
:local cloudflareApiToken "CLOUDFLARE_API_TOKEN"

# ----------------------------------------------------------------------------

# true = check everything but do not change any DNS record.
:local dryRun true

# "auto" tries every public IP service in order until one answers.
# Set "icanhazip", "ipify", "amazon", "ipinfo" or "mikrotik" to use only that service.
# "mikrotik" reads /ip cloud and only works if IP Cloud DDNS is already enabled.
:local publicIpService "auto"

# TLS certificate check for HTTPS requests: "yes", "yes-without-crl" or "no".
# "no" is not recommended: credentials travel in these requests.
:local checkCertificate "yes-without-crl"

# ============================================================================
# Hardcoded values
# ============================================================================

:local logPrefix "MikrotikDDNSUpdater: "

# Public IP services, in the order used by "auto". All of them return IPv4 only.
:local publicIpServiceOrder {"icanhazip"; "ipify"; "amazon"; "ipinfo"; "mikrotik"}
:local publicIpServiceUrls {
    icanhazip="https://ipv4.icanhazip.com";
    ipify="https://api.ipify.org";
    amazon="https://checkip.amazonaws.com";
    ipinfo="https://ipinfo.io/ip"
}

# Addresses that can never be the public IP (private, CGNAT, loopback, link-local,
# multicast, reserved and broadcast), as {network; netmask} pairs.
:local nonPublicRanges {
    {0.0.0.0; 255.0.0.0};
    {10.0.0.0; 255.0.0.0};
    {100.64.0.0; 255.192.0.0};
    {127.0.0.0; 255.0.0.0};
    {169.254.0.0; 255.255.0.0};
    {172.16.0.0; 255.240.0.0};
    {192.168.0.0; 255.255.0.0};
    {224.0.0.0; 240.0.0.0};
    {240.0.0.0; 240.0.0.0}
}

# Cloudflare API.
:local cloudflareApiUrl "https://api.cloudflare.com/client/v4/zones/"

# No-IP update API and authoritative name server (avoids stale cached answers).
:local noipUpdateUrl "https://dynupdate.no-ip.com/nic/update"
:local noipNameServer "nf1.no-ip.com"
# No-IP answers that must be fixed by the user; No-IP may block clients that keep retrying.
:local noipFatalCodes {"nohost"; "badauth"; "badagent"; "!donator"; "abuse"}

# Placeholders used to detect unedited configuration.
:local placeholderHostname "SUBDOMAIN.DOMAIN.COM"
:local placeholderCloudflareApiToken "CLOUDFLARE_API_TOKEN"
:local placeholderCloudflareZoneId "CLOUDFLARE_ZONE_ID"
:local placeholderNoipUsername "USER@DOMAIN.COM"
:local placeholderNoipPassword "PASSWORD"

# Allowed characters for format checks.
:local hostnameChars "abcdefghijklmnopqrstuvwxyz0123456789.-"
:local hexChars "0123456789abcdef"
:local digitChars "0123456789"

# ============================================================================
# Runtime variables
# ============================================================================

:local recordCount 0
:local usesCloudflare false
:local usesNoip false
:local cloudflareHeaders ""
:local noipAuthHeader ""
:local noipNameServerIp ""
:local publicIp ""
# Per-record state, indexed like $records. [:toarray ""] is the documented empty array.
:local recordIds [:toarray ""]
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

:if (($publicIpService != "auto") && \
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
            ($fieldName != "hostname") && ($fieldName != "zoneid"))) do={
            :log error ($logPrefix . "ERROR - record " . ($index + 1) . \
                " has an unknown field (use provider, hostname, zoneid in lowercase)")
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

    # Lowercase letters, digits, dots and hyphens only, with at least one dot.
    :for charIndex from=0 to=([:len $hostname] - 1) do={
        :if ([:typeof [:find $hostnameChars [:pick $hostname $charIndex]]] != "num") do={
            :log error ($logPrefix . "ERROR - invalid hostname (lowercase only): " . $hostname)
            :error ($logPrefix . "invalid hostname")
        }
    }
    :local firstChar [:pick $hostname 0]
    :local lastChar [:pick $hostname ([:len $hostname] - 1)]
    :if (([:typeof [:find $hostname "."]] != "num") || \
        ([:typeof [:find $hostname ".."]] = "num") || \
        ($firstChar = ".") || ($firstChar = "-") || ($lastChar = ".") || ($lastChar = "-")) do={
        :log error ($logPrefix . "ERROR - hostname must be a full domain name: " . $hostname)
        :error ($logPrefix . "invalid hostname")
    }

    :foreach otherIndex,otherRecord in=$records do={
        :if (($otherIndex != $index) && (($otherRecord->"hostname") = $hostname)) do={
            :log error ($logPrefix . "ERROR - hostname is listed twice: " . $hostname)
            :error ($logPrefix . "duplicated hostname")
        }
    }

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
            :log error ($logPrefix . "ERROR - unknown provider for " . $hostname . \
                " (use cloudflare or noip)")
            :error ($logPrefix . "invalid provider")
        }
    }
}

# Credentials are only required for the providers in use.
:if ($usesCloudflare) do={
    :if (([:len $cloudflareApiToken] = 0) || \
        ($cloudflareApiToken = $placeholderCloudflareApiToken)) do={
        :log error ($logPrefix . "ERROR - Cloudflare API token is not set")
        :error ($logPrefix . "Cloudflare API token is not configured")
    }
    :if (([:typeof [:find $cloudflareApiToken " "]] = "num") || \
        ([:typeof [:find $cloudflareApiToken ","]] = "num")) do={
        :log error ($logPrefix . "ERROR - Cloudflare API token contains spaces or commas")
        :error ($logPrefix . "invalid Cloudflare API token")
    }
    # Documented http-header-field format: "name:value,name:value".
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
                # One extra step past the end closes the last octet.
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

:if ([:typeof $publicIp] != "ip") do={
    :log error ($logPrefix . "ERROR - unable to get the public IP from any service")
    :error ($logPrefix . "unable to get the public IP")
}

# ============================================================================
# Get the current IP address of each DNS record
# ============================================================================

:for index from=0 to=($recordCount - 1) do={
    :set recordIds ($recordIds, "")
    :set dnsIps ($dnsIps, "")
    :set needsUpdate ($needsUpdate, false)
    :set recordFailed ($recordFailed, false)
}

# Ask No-IP's own name server; fall back to the router's resolver if it cannot be found.
:if ($usesNoip) do={
    :onerror nameServerError in={
        :set noipNameServerIp [:resolve domain-name=$noipNameServer type=ipv4]
    } do={
        :log warning ($logPrefix . "WARNING - cannot resolve " . $noipNameServer . \
            ", using the router's DNS for No-IP records")
    }
}

:foreach index,record in=$records do={
    :local provider ($record->"provider")
    :local hostname ($record->"hostname")

    :onerror readError in={
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
        } else={
            :if ([:typeof $noipNameServerIp] = "ip") do={
                :set ($dnsIps->$index) [:resolve domain-name=$hostname \
                    server=$noipNameServerIp type=ipv4]
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
        # Cloudflare answers 401/403 without the header fetch expects, so the error text is cryptic.
        :if (($provider = "cloudflare") && (([:typeof [:find $readError "401"]] = "num") || \
            ([:typeof [:find $readError "403"]] = "num"))) do={
            :log error ($logPrefix . "ERROR - check that the Cloudflare API token is valid" . \
                " and can read DNS records of the zone of " . $hostname)
        }
    }
}

# ============================================================================
# Compare the public IP with each DNS record
# ============================================================================

:foreach index,record in=$records do={
    :local hostname ($record->"hostname")

    :if (($recordFailed->$index) = false) do={
        :if ([:tostr ($dnsIps->$index)] = [:tostr $publicIp]) do={
            :log info ($logPrefix . "INFO - " . $hostname . " is up to date")
        } else={
            :set ($needsUpdate->$index) true
            :log info ($logPrefix . "INFO - " . $hostname . " needs update: " . \
                ($dnsIps->$index) . " -> " . $publicIp)
        }
    }
}

# ============================================================================
# Update the DNS records that need it
# ============================================================================

:foreach index,record in=$records do={
    :local provider ($record->"provider")
    :local hostname ($record->"hostname")

    :if (($needsUpdate->$index) = true) do={
        :if ($dryRun) do={
            :log warning ($logPrefix . "WARNING - dry-run, " . $hostname . " not updated to " . $publicIp)
        } else={
            :local noipFatal false
            :onerror updateError in={
                :if ($provider = "cloudflare") do={
                    # Only the content is sent, so proxy status and TTL are kept.
                    :local response [/tool fetch \
                        url=($cloudflareApiUrl . ($record->"zoneid") . "/dns_records/" . ($recordIds->$index)) \
                        http-method=patch http-header-field=$cloudflareHeaders \
                        http-data=("{\"content\":\"" . $publicIp . "\"}") \
                        check-certificate=$checkCertificate output=user as-value]
                    :local responseJson [:deserialize from=json options=json.no-string-conversion \
                        value=($response->"data")]
                    :if (($responseJson->"success") != true) do={
                        :error "Cloudflare answered success=false"
                    }
                    :log info ($logPrefix . "INFO - " . $hostname . " updated to " . $publicIp)
                } else={
                    :local response [/tool fetch \
                        url=($noipUpdateUrl . "?hostname=" . $hostname . "&myip=" . $publicIp) \
                        http-header-field=("Authorization:" . $noipAuthHeader) \
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
                    :local answerCode $answerLine
                    :local answerIp ""
                    :set cutAt [:find $answerLine " "]
                    :if ([:typeof $cutAt] = "num") do={
                        :set answerCode [:pick $answerLine 0 $cutAt]
                        :set answerIp [:pick $answerLine ($cutAt + 1) [:len $answerLine]]
                    }

                    # "good" = updated, "nochg" = already had this IP. Anything else is an error.
                    :if (($answerCode != "good") && ($answerCode != "nochg")) do={
                        :if ([:typeof [:find $noipFatalCodes $answerCode]] = "num") do={
                            :set noipFatal true
                        }
                        :error ("No-IP answered " . $answerLine)
                    }
                    :if ($answerCode = "good") do={
                        :log info ($logPrefix . "INFO - " . $hostname . " updated to " . $publicIp . \
                            " (No-IP: " . $answerLine . ")")
                    } else={
                        :log info ($logPrefix . "INFO - " . $hostname . " already had " . $publicIp . \
                            " (No-IP: " . $answerLine . ")")
                    }
                    :if ($answerIp != [:tostr $publicIp]) do={
                        :log warning ($logPrefix . "WARNING - No-IP did not keep " . $publicIp . \
                            " for " . $hostname)
                    }
                }
                :set updatedCount ($updatedCount + 1)
            } do={
                :set failedCount ($failedCount + 1)
                :log error ($logPrefix . "ERROR - cannot update " . $hostname . ": " . $updateError)
                # Authentication errors come back as HTTP 401/403 before any answer can be read.
                :local authError (([:typeof [:find $updateError "401"]] = "num") || \
                    ([:typeof [:find $updateError "403"]] = "num"))
                :if (($provider = "cloudflare") && $authError) do={
                    :log error ($logPrefix . "ERROR - check that the Cloudflare API token can edit" . \
                        " DNS records of the zone of " . $hostname)
                }
                :if (($provider = "noip") && ($noipFatal || $authError)) do={
                    :log error ($logPrefix . "ERROR - fix the No-IP account or hostname now:" . \
                        " No-IP may block clients that keep sending failing updates")
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
