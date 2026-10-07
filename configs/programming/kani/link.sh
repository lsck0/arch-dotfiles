#!/usr/bin/env bash

[[ -d "${HOME}/.kani/kani-$(cargo-kani --version | awk 'NR==1{print $4}')" ]] || cargo kani setup
