#!/bin/bash

set -e

HOSTNAME=${1}

nc -w1 ${HOSTNAME} 22; echo $?
nc -w1 ${HOSTNAME} 443; echo $?
