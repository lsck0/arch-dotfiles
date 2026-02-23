#!/usr/bin/env bash

set -ex

cargo install --locked kani-verifier
cargo kani setup
