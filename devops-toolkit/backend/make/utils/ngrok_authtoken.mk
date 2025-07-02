# ---------------------------------------
# Ngrok authtoken for local development
#
# These constants are not sensitive, and hence, are made available for Poof backend services.
# ---------------------------------------

SHELL := /bin/bash


# --------------------------------
# External Variable Validation
# --------------------------------

# Runtime/Ci environment variables #

ifneq ($(origin NGROK_AUTHTOKEN), environment)
  $(error NGROK_AUTHTOKEN is either not set or set in the root Makefile. Please define it in your runtime/ci environment only. \
  Example: export NGROK_AUTHTOKEN="********")
endif

# ---------------------------------
# Internal Variable Declaration
# ---------------------------------

# Removed default ngrok authtoken...caused conflicts with people who forgot to set theirs):

INCLUDED_NGROK_AUTHTOKEN := 1
