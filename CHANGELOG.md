# CHANGELOG

## 1.0.0 (unreleased)

First release!

* Index every gem of the bundle at the end of `bundle install`: `after-install` queues each gem, `after-install-all` indexes the queue, so indexing never holds up an install worker
* Add the `bundle codegraph-index [--force]` command to catch up on an already installed bundle
* Serialize indexing through an advisory file lock, so concurrent `bundle install` runs do not run several indexers at once; the lock lives in a private per-user directory, so another user of a shared `/tmp` cannot hold it
* Skip gems carrying no Ruby source, and have the hook skip gems already holding a `.codegraph/` directory
* Sync existing indexes from `bundle codegraph-index`, which completes one a killed run left partial
* Remove the `.codegraph/` directory of a failed or interrupted run, and restore the previous index when a `--force` rebuild fails
* Turn the plugin into a no-op when the `codegraph` binary is missing, rather than failing the install
* Run `codegraph` with its stdin on `/dev/null`, so a prompt it would show can never hang `bundle install`
* Find Ruby sources under a path holding glob metacharacters (`[`, `{`) instead of skipping every gem as `no Ruby source`
* Leave `bundler` and the project's own gemspec out of both the hook and `bundle codegraph-index`
* Warn about each gem `codegraph` fails on, and keep its error output in a per-gem log file
* Add the `BUNDLER_CODEGRAPH`, `BUNDLER_CODEGRAPH_EXCLUDE` and `BUNDLER_CODEGRAPH_BIN` environment variables
