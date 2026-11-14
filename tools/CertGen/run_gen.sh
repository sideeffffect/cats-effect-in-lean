#!/bin/bash
set -e
cd "$(dirname "$0")/../.."
SP=${CERTGEN_OLEAN:-/tmp/certgen-olean}
L=${LAKE:-lake}
mkdir -p $SP/CertGen
$L env lean tools/CertGen/Gen.lean -o $SP/CertGen/Gen.olean
LP=$($L env printenv LEAN_PATH)
time LEAN_PATH=$SP:$LP $L env lean --run "$1"
