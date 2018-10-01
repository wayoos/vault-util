#!/bin/bash

set -e

function d_usage() {
    echo "Vaultutil"
    echo "Usage: $0 {init|unseal|update}"
    exit 1
}

function check_setup() {
    if ! [ -x "$(command -v vault)" ]; then
        echo 'Error: vault is not installed.' >&2
        exit 1
    fi

    if [[ -z "$VAULT_ADDR" ]]; then
        echo "Vault address is not define. Export it with:"
        echo ""
        echo "export VAULT_ADDR=http://vault"
        echo ""
        exit 1
    fi
}

function d_login() {
    local role_id=$1
    local token=$(vault write -format=json auth/approle/login role_id=$role_id | jq -r '.auth.client_token')
    if [[ ${token//-/} =~ ^[[:xdigit:]]{32}$ ]]; then
        echo $token
    else
        echo "Invalid token"
        exit 1
    fi
}

check_setup

cmd=$1
shift
case "$cmd" in
    login)
        d_login $*
        ;;
    *)
        d_usage 
esac
