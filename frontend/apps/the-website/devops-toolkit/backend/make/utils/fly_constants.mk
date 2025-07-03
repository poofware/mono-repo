# ---------------------------------------
# Constants and Variables for Fly.io configuration
#
# Some of these variables are not sensitive, and hence, are constants made available for Poof backend services.
# ---------------------------------------

SHELL := /bin/bash


FLY_STAGING_ORG_NAME := poof-staging
FLY_WIREGUARD_CONF_FILE := ./fly.conf
FLY_WIREGUARD_PEER_REGION := iad

INCLUDED_FLY_CONSTANTS := 1
