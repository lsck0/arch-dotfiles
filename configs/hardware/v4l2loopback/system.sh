#!/usr/bin/env bash

install -Dm644 v4l2loopback.conf /etc/modules-load.d/v4l2loopback.conf
install -Dm644 v4l2loopback-options.conf /etc/modprobe.d/v4l2loopback.conf
