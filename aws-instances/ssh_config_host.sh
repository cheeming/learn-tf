HOST=${1}
PUBLIC_IP=${2}

cat << EOF

Host ${HOST}
    Hostname ${PUBLIC_IP}
    User ubuntu
    IdentityFile ~/.ssh/id_aws

EOF
