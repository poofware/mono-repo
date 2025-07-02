# ---------------------------------------------
# Constants for LaunchDarkly (LD) configuration
#
# These constants are not sensitive, and hence, are made available for Poof backend services.
# ---------------------------------------------

SHELL := /bin/bash

INCLUDED_LAUNCHDARKLY_CONSTANTS := 1


export LD_SERVER_CONTEXT_KEY := server
export LD_SERVER_CONTEXT_KIND := user
