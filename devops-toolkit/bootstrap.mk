###############################################################################
#  devops-toolkit/bootstrap.mk
#  • Sets DEVOPS_TOOLKIT – directory of this file (always succeeds)
#  • Sets REPO_ROOT      – caller-supplied, or git-derived, or safe fallback
#  • Adds toolkit path to make’s include search (-I)
###############################################################################
# ── 1. locate the toolkit itself (no external commands) ──────────────────────
DEVOPS_TOOLKIT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
export DEVOPS_TOOLKIT

# ── 2. establish REPO_ROOT if caller hasn’t ──────────────────────────────────
ifeq ($(origin REPO_ROOT), undefined)
  # first try Git
  REPO_ROOT := $(shell git -C $(DEVOPS_TOOLKIT) rev-parse --show-toplevel 2>/dev/null)

  ifeq ($(REPO_ROOT),)                     # git failed → fallback + warning
    REPO_ROOT := $(abspath $(DEVOPS_TOOLKIT)/..)
    yellow := \033[33m
    normal := \033[0m
    $(warning $(yellow)[bootstrap] git rev-parse failed; \
              falling back to $(REPO_ROOT)$(normal))
  endif
endif
export REPO_ROOT

# ── 3. make every “include shared/…” resolve from anywhere ───────────────────
MAKEFLAGS += -I$(DEVOPS_TOOLKIT)

INCLUDED_TOOLKIT_BOOTSTRAP := 1
