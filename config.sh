#!/bin/sh

export DISTRIBS_DEB="ubuntu-bionic \
  ubuntu-focal \
  ubuntu-jammy \
  debian-buster \
  debian-bullseye"
export DISTRIBS_RPM="centos-7 centos-8"
# Old distributives that are just broken on aarch64
export ARM_BLACKLIST="ubuntu-bionic"

# Can be overriden (e.g. adding a username)
export SSH_CMD="ssh"
export SCP_CMD="scp"
export TARGET_DIR="./out"

# Must be overriden
export SSH_HOST_X86="example.com"
export SSH_HOST_AARCH64="example.com"

export RSPAMD_VER_UNSTABLE="3.5"
export RSPAMD_VER_STABLE="3.4"

if [ -n "${STABLE}" ] ; then
  export RSPAMD_VER="${RSPAMD_VER_STABLE}"
  export STABLE_VER="1"
else
  export RSPAMD_VER="${RSPAMD_VER_UNSTABLE}"
fi

export KEY="3FA347D5E599BE4595CA2576FFA232EDBF21E25E"

if [ -f "./config.local.sh" ] ; then
  . ./config.local.sh
fi
