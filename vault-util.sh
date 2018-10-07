#!/bin/bash
set -e

SCRIPT_NAME=$0
CMD=$1


function d_usage() {
    echo "Usage: $0 {cert|generate-ca|generate-rootca|login|pki-role} [--help]"
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
    local role_id=$1
    local token=$(vault write -format=json auth/approle/login role_id=$role_id | jq -r '.auth.client_token')
    if [[ ${token//-/} =~ ^[[:xdigit:]]{32}$ ]]; then
        echo $token
    else
        echo "Invalid token"
        exit 1
    fi
}

function d_generate_rootca() {
    local name=$1
    local description=$2
    local max_lease_ttl=$3
    local max_lease_ttl=${max_lease_ttl:=87600h}

    if [[ $1 == "--help" || -z $name || -z $description ]]; then
        echo "Usage: $SCRIPT_NAME $CMD <name> <description> [max_lease_ttl]"
        exit 1
    fi

    secrets_enable pki $name "$description" $max_lease_ttl

    set +e
    vault read $name/cert/ca > /dev/null 2>&1
    ca_created=$?
    set -e
    if [[ "$ca_created" != "0" ]]; then
        echo "Generate certificate $name"
        vault write $name/root/generate/internal common_name="$description" \
            ttl=$max_lease_ttl key_bits=4096 exclude_cn_from_sans=true > /dev/null 2>&1
    fi
}

function d_generate_ca() {
    if [[ $1 == "--help" || $# -lt 3 ]]; then
        echo "Usage: $SCRIPT_NAME $CMD <name> <description> <rootca> [max_lease_ttl]"
        exit 1
    fi

    local name=$1
    local description=$2
    local rootca=$3
    local max_lease_ttl=$4
    local max_lease_ttl=${max_lease_ttl:=26280h}

    secrets_enable pki $name "$description" $max_lease_ttl

    set +e
    vault read $name/cert/ca > /dev/null 2>&1
    ca_created=$?
    set -e
    if [[ "$ca_created" != "0" ]]; then
        echo "Generate certificate $name"
        vault write -format=json $name/intermediate/generate/internal common_name="$description" \
            ttl=$max_lease_ttl key_bits=4096 exclude_cn_from_sans=true | jq -r .data.csr | \
            vault write -format=json $rootca/root/sign-intermediate csr=- ttl=$max_lease_ttl use_csr_values=true | jq -r .data.certificate | \
            vault write $name/intermediate/set-signed certificate=-
    fi
}

function d_pki_role() {
    if [[ $1 == "--help" || $# -lt 3 ]]; then
        echo "Usage: $SCRIPT_NAME $CMD <name> <roleName> <parameters>"
        exit 1
    fi

    local secret_name=$1
    local role_name=$2
    local parameters=$3

    set +e
    vault read $secret_name/roles/$role_name > /dev/null 2>&1
    role_created=$?
    set -e
    if [[ "$role_created" != "0" ]]; then
        vault write $secret_name/roles/$role_name $parameters
    fi

}

function d_cert() {
    if [[ $1 == "--help" || $# -lt 4 ]]; then
        echo "Usage: $SCRIPT_NAME $CMD <name> <roleName> <parameters> <outputFile>"
        exit 1
    fi

    local secret_name=$1
    local role_name=$2
    local parameters=$3
    local outputFile=$4

    vault write -format=json $secret_name/issue/$role_name $parameters > $outputFile.json

    cat $outputFile.json | jq -r .data.private_key > $outputFile-key.pem
    cat $outputFile.json | jq -r .data.certificate > $outputFile.pem
    cat $outputFile.json | jq -r .data.certificate > $outputFile-full.pem
    cat $outputFile.json | jq -r .data.issuing_ca >> $outputFile-full.pem
    cat $outputFile.json | jq -r .data.ca_chain[0] >> $outputFile-full.pem

    rm $outputFile.json
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
    fi
}

set +e
shift
set -e

check_setup

if [[ $CMD != "login" ]]; then
    check_token
fi

case "$CMD" in
    login)
        d_login $*
        ;;
    generate-ca)
        d_generate_ca $1 "$2" $3 $4
        ;;
    generate-rootca)
        d_generate_rootca $1 "$2" $3
        ;;
    pki-role)
        d_pki_role $1 $2 "$3"
        ;;
    cert)
        d_cert $1 $2 "$3" $4
        ;;
    *)
        d_usage
        ;;
esac
