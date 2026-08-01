# ============================================================================
# Module version
# ============================================================================
# A Terraform module has no runtime knowledge of the source version it was
# fetched as — `?ref=v0.9.0` is invisible to HCL, and git tags are not readable
# from inside a plan. Without a constant here, no diagnostic can say WHICH
# version is running, which is exactly what a consumer needs when an extension
# they configured silently does nothing (see docs/EXTENSIONS.md).
#
# This is hand-maintained and therefore capable of lying. `make check-version`
# asserts it matches the newest CHANGELOG heading; run it in CI and at release.
#
# It states the version this checkout WILL BE released as, not the last tag —
# CHANGELOG.md is written the same way.

locals {
  module_version = "0.11.0"
}
