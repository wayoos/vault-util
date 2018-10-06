#!/bin/bash

set -e

COMMAND_NAME=$0

function d_usage() {
    echo "Usage: $0 {login|generate-ca} [--help]"
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

function check_token() {
    if [[ -z "$VAULT_TOKEN" ]]; then
        echo "Vault token is not define. Export it with:"
        echo ""
        echo "export VAULT_TOKEN=XXXX-XXXX"
        echo ""
        exit 1
    fi
}

function d_login() {
    check_setup

    local role_id=$1
    local token=$(vault write -format=json auth/approle/login role_id=$role_id | jq -r '.auth.client_token')
    if [[ ${token//-/} =~ ^[[:xdigit:]]{32}$ ]]; then
        echo $token
    else
        echo "Invalid token"
        exit 1
    fi
}

function d_generate_ca() {
    check_setup
    check_token
    if [[ $1 == "--help" || $# -lt 2 ]]; then
        echo "Usage: $COMMAND_NAME generate-ca <name> <description> [max_lease_ttl]"
        exit 1
    fi

    local name=$1
    local description=$2
    local max_lease_ttl=$3

    secrets_enable pki $name "$description" $max_lease_ttl
}

#-------------------------
# Enable secrets of type with defined path.
# If already exist, do nothings.
function secrets_enable() {
    local secrets_type=$1
    local secrets_path=$2
    local secrets_description=$3
    local max_lease_ttl=$4
    local max_lease_ttl=${max_lease_ttl:=26280h}

    local installed=$(vault secrets list -format=json | jq '."'$secrets_path'/" | .type == "'$secrets_type'"')
    if [[ "$installed" != "true" ]]; then
        vault secrets enable -path=$secrets_path -description="${secrets_description}" -max-lease-ttl=$max_lease_ttl $secrets_type
        return 1
    fi
    return 0
}

cmd=$1
set +e
shift
set -e
case "$cmd" in
    login)
        d_login $*
        ;;
    generate-ca)
        d_generate_ca $1 "$2" $3
        ;;
    *)
        d_usage
        ;;
esac
