#!/usr/bin/env bash

# Set up fully the test environment (except for installing required sw packages other than node and php): mysql, nodejs, php, composer, eZ, etc...
# Has to be useable from the Docker test container as well as locally in Travis and GH-hosted runners.
# Has to be run from the project (bundle) top dir.
#
# Uses env vars: TRAVIS, PHP_VERSION, NODE_VERSION, GITHUB_ACTION

# @todo check if all required env vars have a value
# @todo support a -v option
# @todo allow executing a specified set of tasks instead of all of them

set -e

BIN_DIR="$(dirname -- "${BASH_SOURCE[0]}")"

# @todo since we can set the php version both on on Travis/GHA and Containers, it makes sense to use PHP_VERSION
#       everywhere and drop TESTSTACK_PHP_VERSION. Atm we keep making use of it for BC.
#       Note: what about TRAVIS_PHP_VERSION then? We still use it in some setup scripts, even though it is not reliable anymore
if [ -n "${TESTSTACK_PHP_VERSION}" ]; then
    if [ -z "${PHP_VERSION}" ]; then
        export PHP_VERSION="${TESTSTACK_PHP_VERSION}"
    else
        if [ "${TESTSTACK_PHP_VERSION}" != "${PHP_VERSION}" ]; then
            printf "\n\e[31mERROR:\e[0m env var TESTSTACK_PHP_VERSION is set and different from PHP_VERSION\n\n" >&2
            exit 1
        fi
    fi
fi
if [ -n "${TESTSTACK_NODE_VERSION}" ]; then
    if [ -z "${NODE_VERSION}" ]; then
        export NODE_VERSION="${TESTSTACK_NODE_VERSION}"
    else
        if [ "${TESTSTACK_NODE_VERSION}" != "${NODE_VERSION}" ]; then
            printf "\n\e[31mERROR:\e[0m env var TESTSTACK_NODE_VERSION is set and different from NODE_VERSION\n\n" >&2
            exit 1
        fi
    fi
fi

# For php 5.6, Composer needs humongous amounts of ram - which we don't have on Travis. Enable swap as workaround
# @todo we could probably disable this when EZ_COMPOSER_LOCK is used instead of EZ_PACKAGES
if [ "${PHP_VERSION}" = "5.6" -a -n "${TRAVIS}" ]; then
    echo "Setting up a swap file..."

    # @todo any other services we could stop ?
    sudo systemctl stop cron atd docker snapd mysql

    sudo fallocate -l 10G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    sudo swapon -s

    sudo sysctl vm.swappiness=10
    sudo sysctl vm.vfs_cache_pressure=50

    #free -m
    #df -h
    #ps auxwww
    #systemctl list-units --type=service
fi

if [ -n "${NODE_VERSION}" ]; then
    "${BIN_DIR}/setup/node.sh"
fi

if [ -n "${PHP_VERSION}" ]; then
    "${BIN_DIR}/setup/php.sh"
fi

"${BIN_DIR}/setup/php-config.sh"

# This is done by Travis automatically... Check if on GHA we also always get the latest version
#if [ "${TRAVIS}" != "true" ]; then
#    composer selfupdate
#fi

"${BIN_DIR}/setup/composer.sh"

"${BIN_DIR}/setup/composer-dependencies.sh"

# When this is run in the test container, the db server is in another container. No need to try to configure it remotely.
# Otoh, when running on Travis or GHA, the db server runs within the same VM
if [ -n "${TRAVIS}" -o -n "${GITHUB_ACTION}" ]; then
    "${BIN_DIR}/setup/db-config.sh"
fi

source "$(dirname -- "${BASH_SOURCE[0]}")/set-env-vars.sh"
if [ "${EZ_VERSION}" != "ezplatform3" -a "${EZ_VERSION}" != "ezplatform33"  -a "${EZ_VERSION}" != "ezplatform4" ]; then
    # Create the database from sql files present in either the legacy stack or kernel (has to be run after composer install)
    "${BIN_DIR}/create-db.sh"
    # Set up eZ configuration files (if ez legacy is installed, this runs a legacy script, which might fail with no db schema available)
    "${BIN_DIR}/setup/ez-config.sh"
else
    # For eZPlatform 3 and 4, we have to swap the order of execution
    "${BIN_DIR}/setup/ez-config.sh"
    "${BIN_DIR}/create-db.sh"
fi

# TODO are these needed at all? Also: are they available / the same for every eZP version?
#"${BIN_DIR}/sfconsole.sh" cache:clear --no-debug
#"${BIN_DIR}/sfconsole.sh" assetic:dump

# TODO for eZPlatform, do we need to set up SOLR as well ? (Note that ezpl3.3 has a different folder name)
#if [ "$EZ_VERSION" != "ezpublish" ]; then ./vendor/ezsystems/ezplatform-solr-search-engine && bin/.travis/init_solr.sh; fi

echo "Setup done"
