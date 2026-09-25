# CHANGELOG

## 1.0.0 (unreleased)

First release!

* Index every gem right after Bundler installs it, through the `after-install` hook
* Add the `bundle codegraph-index [--force]` command to catch up on an already installed bundle
* Serialize indexing through an advisory file lock, so parallel install workers do not run several indexers at once
* Skip gems carrying no Ruby source, and have the hook skip gems already holding a `.codegraph/` directory
* Sync existing indexes from `bundle codegraph-index`, which completes one a killed run left partial
* Remove the `.codegraph/` directory of a failed or interrupted run, and restore the previous index when a `--force` rebuild fails
* Turn the plugin into a no-op when the `codegraph` binary is missing, rather than failing the install
* Add the `BUNDLER_CODEGRAPH`, `BUNDLER_CODEGRAPH_EXCLUDE` and `BUNDLER_CODEGRAPH_BIN` environment variables
