#!rsc by RouterOS
# MikroTikDDNSUpdater
# Build: 8
#
# https://github.com/lolostt/MikrotikDDNSUpdater
# Copyright (C) 2024 Sleeping Coconut https://sleepingcoconut.com
#
#
# This script updates dynamic DNS service using current public IP.
#
# Usage:
#    1. Fill "Variables" section below.
#    2. Place script in MikroTik device using Winbox, WebFig or terminal.
#    3. Give "read", "write" and "test" permissions.
#    4. You can automate execution using RouterOS scheduler. Check README.


# --------------------------------------------------------------------------------------------------
# Variables ( MANDATORY EDIT!!! )

:local DomainName "subdomain.domain.com";

# Dynamic DNS service:
#   "1" for DNS-O-Matic
#   "2" for No-IP
:local DDNSService "1";
:local DDNSUserName "user@domain.com"; # Dynamic DNS service user name.
:local DDNSUserPassword "password"; # Dynamic DNS service user password.

# Public IP determination mode:
#   "1" icanhazip (default)
#   "2" AWS
#   "3" DNS-O-Matic
#   "9" Mikrotik Cloud Services
:local PublicIPServiceMode "1";
:local MikroTikCloudHostName "SERIALNUMBER.sn.mynetname.net"; # Optional. # Needed if using mode 9

# Other options:
:local VerboseMode false;
:local RequestWait 5; # [seconds]
:local DisableDomainIPAddressCheck false;

# --------------------------------------------------------------------------------------------------
# Hardcoded variables ( DO NOT EDIT unless you want to edit a service )

:local DDNSServiceNames { \
  "1"="DNS-O-Matic"; \
  "2"="No-IP" };

:local DDNSServiceURLs { \
  "1"="https://updates.dnsomatic.com/nic/update\3F"; \
  "2"="https://dynupdate.no-ip.com/nic/update\3F" };

# Public IP determination services
:local PublicIPServiceURLs { \
  "1"="https://icanhazip.com/"; \
  "2"="https://checkip.amazonaws.com/"; \
  "3"="https://myip.dnsomatic.com/" };

# --------------------------------------------------------------------------------------------------
# Runtime variables ( DO NOT EDIT )

:local currentPublicIPAddress "0.0.0.0";
:local currentDomainIPAddress "0.0.0.0";
:local APIURLWithArgs;
:local APIResponse;
:local RequestWaitConverted [:totime $RequestWait];
:local PublicIPServiceURLSelected;

# --------------------------------------------------------------------------------------------------
# Functions

:global endScript do={
    :log error $message;
    :error $message;
};

:global checkDefaults do={
    :if ( $DomainName = "subdomain.domain.com" ) do={
        :log error "MikroTikDDNSUpdater: Domain not configured";
        :error "MikroTikDDNSUpdater: Domain not configured";
    };
    :if ( $DDNSUserName = "user@domain.com" || \
          $DDNSUserPassword = "password" ) do={
        :log error "MikroTikDDNSUpdater: DNS service credentials not configured";
        :error "MikroTikDDNSUpdater: DNS service credentials not configured";
    };
    :if ( $DisablePublicIPAddressCheck = false ) do={
        :if ( $PublicIPServiceMode = "9" && \
              $MikroTikCloudHostName = "SERIALNUMBER.sn.mynetname.net" ) do={
            :log error "MikroTikDDNSUpdater: MikroTikCloudHostName variable not configured";
            :error "MikroTikDDNSUpdater: MikroTikCloudHostName variable not configured";
        };
    };
};

:global getPublicIP do={
    :local currentIP "0.0.0.0";
    :do {
        :if ( $mode = "1" || $mode = "2" || $mode = "3" ) do={
            :set currentIP ([/tool fetch mode=https \
                                         url=$publicIPServiceURL \
                                         as-value output=user]->"data");
            :delay $requestWait;
            :local lastCharacterIndex [:put ([:len $currentIP] - 1)];
            :local lastCharacter [:pick $currentIP $lastCharacterIndex];
            :if ( $lastCharacter = "\n" ) do={
                :local cleanCurrentIP [:pick $currentIP 0 $lastCharacterIndex];
                :return $cleanCurrentIP;
            } else {
                :return $currentIP;    
            };
        };
        :if ( $mode = "9" ) do={
            /ip cloud force-update;
            :delay $requestWait;
            :set currentIP [resolve domain-name=$cloudName];
            :return $currentIP;
        };
        :if ( $mode != 1 && $mode != 2 && $mode != 3 && $mode != 9) do={
            :return "invalid mode";
        };
    } on-error={
        :return "0.0.0.0";
    };
};

:global getDomainIP do={
    :do {
        :local currentDomainIP [resolve domain-name=$url];
        :return $currentDomainIP;
    } on-error={
        :return "0.0.0.0";
    };
};

:global APICall do={
    :do {
        /tool fetch \
          mode=https \
          user="$userName" \
          password="$userPassword" \
          url="$url" \
          keep-result=no;
        :delay $requestWait;
        :return 0;
    } on-error={
        :return 1;
    };
};

# --------------------------------------------------------------------------------------------------
# Script

:if ( $VerboseMode = true ) do={ :log info "MikroTikDDNSUpdater: script starting"; };

:if ( $VerboseMode = true ) do={ 
    :local message1 ("MikroTikDDNSUpdater: selected " \
      . \
      ($DDNSServiceNames->"$DDNSService") . " service");
    :log info $message1;
    :local message2 ("MikroTikDDNSUpdater: selected mode $PublicIPServiceMode");
    :log info $message2;
};

# ----------
# Stage 1: check variables

$checkDefaults DomainName=$DomainName \
               DDNSUserName=$DDNSUserName \
               DDNSUserPassword=$DDNSUserPassword \
               PublicIPServiceMode=$PublicIPServiceMode \
               MikroTikCloudHostName=$MikroTikCloudHostName;

# ----------
# Stage 2: public IP

# Stage 2a: get public IP address

:set PublicIPServiceURLSelected ($PublicIPServiceURLs->"$PublicIPServiceMode");
:set currentPublicIPAddress [$getPublicIP mode=$PublicIPServiceMode \
                                          publicIPServiceURL=$PublicIPServiceURLSelected \
                                          cloudName=$MikroTikCloudHostName \
                                          requestWait=$RequestWaitConverted;]

# Stage 2b: check public IP address

:if ( $currentPublicIPAddress = "0.0.0.0" ||  \
     $currentPublicIPAddress = nil ||  \
     $currentPublicIPAddress = "invalid mode" ) do={
    :if ( $currentPublicIPAddress = "invalid mode" ) do={
        $endScript message="MikroTikDDNSUpdater: invalid PublicIPServiceMode";
    } else {
        $endScript message="MikroTikDDNSUpdater: public IP address determination failed";
    };
} else {
    :if ( $VerboseMode = true ) do={
        :log info "MikroTikDDNSUpdater: public IP address is $currentPublicIPAddress";
    };
};

# ----------
# Stage 3: domain IP

:if ( $DisableDomainIPAddressCheck = false ) do={

    # Stage 3a: get domain IP address

    :set currentDomainIPAddress [$getDomainIP url=$DomainName;]

    # Stage 3b: check domain IP address

    :if ( $currentDomainIPAddress = "0.0.0.0" || \
         $currentDomainIPAddress = nil ) do={
        $endScript message="MikroTikDDNSUpdater: domain IP address determination failed";
    } else {
        :if ( $VerboseMode = true ) do={
            :log info "MikroTikDDNSUpdater: domain IP address is $currentDomainIPAddress";
        };
    };
};

# ----------
# Stage 4: IP addresses comparison and API call

:if ( $DisableDomainIPAddressCheck = false ) do={

    # Stage 4a: compare IP addresses

    :if ( $currentPublicIPAddress = $currentDomainIPAddress ) do={
        :log info "MikroTikDDNSUpdater: update not needed for $DomainName";
    } else {

    # Stage 4b: call API

        :set APIURLWithArgs (($DDNSServiceURLs->"$DDNSService") \
          . \
          "hostname=$DomainName&myip=$currentPublicIPAddress");

        :if ( $VerboseMode = true ) do={
            :log info "MikroTikDDNSUpdater: calling API with url: $APIURLWithArgs";
        };

        :set APIResponse [
            $APICall url=$APIURLWithArgs \
              userName=$DDNSUserName \
              userPassword=$DDNSUserPassword \
              requestWait=$RequestWaitConverted;
        ]

        :if ( $APIResponse = 0 ) do={
            :log info "MikroTikDDNSUpdater: $DomainName updated from \
              $currentDomainIPAddress to $currentPublicIPAddress";
        } else {
            $endScript message="MikroTikDDNSUpdater: DDNS service API call failed";
        };
    };

} else {

    # Stage 4b: call API

    :set APIURLWithArgs (($DDNSServiceURLs->"$DDNSService") \
      . \
      "hostname=$DomainName&myip=$currentPublicIPAddress");

    :if ( $VerboseMode = true ) do={
        :log info "MikroTikDDNSUpdater: calling API with url: $APIURLWithArgs";
    };

    :set APIResponse [
        $APICall url=$APIURLWithArgs \
          userName=$DDNSUserName \
          userPassword=$DDNSUserPassword \
          requestWait=$RequestWaitConverted;
    ]

    :if ( $APIResponse = 0 ) do={
        :log info "MikroTikDDNSUpdater: $DomainName updated to $currentPublicIPAddress";
    } else {
        $endScript message="MikroTikDDNSUpdater: DDNS service API call failed";
    };
};

# ----------
# Final stage:

:if ( $VerboseMode = true ) do={ :log info "MikroTikDDNSUpdater: script ended"; };

# --------------------------------------------------------------------------------------------------