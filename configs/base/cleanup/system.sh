#!/usr/bin/env bash

# journald size cap, copied (journald reads /etc before /home mounts); restart only on change, a restart rotates the journal
if file_update journald-size.conf /etc/systemd/journald.conf.d/00-size.conf; then
    systemctl restart systemd-journald.service
fi
