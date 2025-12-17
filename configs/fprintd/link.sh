#!/usr/bin/env bash

set -ex

# allow fingerprint login and sudo
awk '
  /^auth/ { last_auth=NR }
  { lines[NR]=$0 }
  END {
    for (i=1; i<=NR; i++) {
      print lines[i]
      if (i==last_auth)
        print "auth    sufficient    pam_fprintd.so"
    }
  }
' /etc/pam.d/system-login | sudo tee /etc/pam.d/system-login > /dev/null
awk '
  /^auth/ { last_auth=NR }
  { lines[NR]=$0 }
  END {
    for (i=1; i<=NR; i++) {
      print lines[i]
      if (i==last_auth)
        print "auth    sufficient    pam_fprintd.so"
    }
  }
' /etc/pam.d/sudo | sudo tee /etc/pam.d/sudo > /dev/null
