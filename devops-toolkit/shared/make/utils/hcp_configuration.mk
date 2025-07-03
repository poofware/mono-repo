# ---------------------------------------
# Constants and Variables for HCP (HashiCorp Cloud Platform) configuration
#
# Some of these variables are not sensitive, and hence, are constants made available for Poof backend services.
# ---------------------------------------

SHELL := /bin/bash

ifndef INCLUDED_TOOLKIT_BOOTSTRAP
  $(error [toolkit] bootstrap.mk not included before $(lastword $(MAKEFILE_LIST)))
endif


# --------------------------------
# External Variable Validation
# --------------------------------

# Runtime/Ci environment variables #

# Will need the client id and client secret to fetch the HCP API token
# if HCP_ENCRYPTED_API_TOKEN is not already set
ifndef HCP_ENCRYPTED_API_TOKEN
  ifneq ($(origin HCP_CLIENT_ID), environment)
    $(error HCP_CLIENT_ID is either not set or set in the root Makefile. Please define it in your runtime/ci environment only. \
	  Example: export HCP_CLIENT_ID="my_client_id")
  endif

  ifneq ($(origin HCP_CLIENT_SECRET), environment)
    $(error HCP_CLIENT_SECRET is either not set or set in the root Makefile. Please define it in your runtime/ci environment only. \
      Example: export HCP_CLIENT_SECRET="my_client_secret")
  endif
endif

ifneq ($(origin HCP_TOKEN_ENC_KEY), environment)
  $(error HCP_TOKEN_ENC_KEY is either not set or set in the root Makefile. Please define it in your runtime/ci environment only. \
    Example: export HCP_TOKEN_ENC_KEY="my_encryption_key")
endif


# ---------------------------------
# Internal Variable Declaration
# ---------------------------------

# To force a static assignment operation with '?=' behavior, we wrap the ':=' assignment in an ifndef check
ifndef HCP_ENCRYPTED_API_TOKEN
  export HCP_ENCRYPTED_API_TOKEN := $(shell $(DEVOPS_TOOLKIT_PATH)/shared/scripts/fetch_hcp_api_token.sh encrypted)
  $(if $(HCP_ENCRYPTED_API_TOKEN),,$(error Failed to fetch HCP encrypted API token))
  export HCP_API_TOKEN := $(shell $(DEVOPS_TOOLKIT_PATH)/shared/scripts/fetch_hcp_api_token.sh)
  $(if $(HCP_API_TOKEN),,$(error Failed to fetch HCP API token))
endif

# Poof
export HCP_ORG_ID := a4c32123-5c1c-45cd-ad4e-9fe42a30d664
# Backend
export HCP_PROJECT_ID := d413f61e-00f1-4ddf-afaf-bf8b9c04957e


INCLUDED_HCP_CONFIGURATION := 1
