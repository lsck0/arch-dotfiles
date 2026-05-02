#!/usr/bin/env bash

set -ex

## reset jai directory

rm -rf ~/.jai
mkdir -p ~/.jai

## jai itself

wget $1 -O ~/.jai/jai.zip
unzip ~/.jai/jai.zip -d ~/.jai
mv ~/.jai/jai/* ~/.jai/
rmdir ~/.jai/jai

## jai language server

git clone --recursive https://github.com/SogoCZE/Jails.git ~/.jai/jails
pushd ~/.jai/jails
jai-linux build.jai
popd

ln -sf ~/.jai/jails/bin/jails ~/.jai/bin/jails
