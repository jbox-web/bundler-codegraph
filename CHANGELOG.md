# CHANGELOG

## 0.1.0 (2026-09-25)

First release!

* Index every gem of the bundle at the end of `bundle install`: `after-install` queues each gem, `after-install-all` indexes the queue, so indexing never holds up an install worker; each gem indexed prints a line
* Add the `bundle codegraph-index [--force]` command to catch up on an already installed bundle; `--help` prints its usage; it exits non-zero on an unknown argument, a missing `codegraph` binary, or any gem failing to index
* Serialize indexing through an advisory file lock, so concurrent `bundle install` runs do not run several indexers at once; the lock lives in a private per-user directory, so another user of a shared `/tmp` cannot hold it, and both the hook and `bundle codegraph-index` warn when that directory cannot be trusted
* Stop `codegraph` (TERM, then KILL) before cleaning up when `bundle install` is interrupted, even when the signal reaches Ruby alone
* Skip gems carrying no Ruby source, and have the hook skip gems already holding an index (`.codegraph/codegraph.db`)
* Sync existing indexes from `bundle codegraph-index`, which completes one a killed run left partial
* Remove the `.codegraph/` directory of a failed or interrupted run, and restore the previous index when a `--force` rebuild fails or is killed
* Turn the plugin into a no-op when the `codegraph` binary is missing, rather than failing the install
* Run `codegraph` with its stdin on `/dev/null`, so a prompt it would show can never hang `bundle install`
* Find Ruby sources under a path holding glob metacharacters (`[`, `{`) instead of skipping every gem as `no Ruby source`
* Leave `bundler` and the project's own gemspec out of both the hook and `bundle codegraph-index`
* Warn about each gem `codegraph` fails on, and keep its error output in a per-gem log file; the hook says it skips that gem, and does not retry it until a new version of it is installed, `bundle codegraph-index` runs, or the temporary directory is purged; an interrupted run, or a `codegraph` killed by a signal, is not recorded as a failure
* Add the `BUNDLER_CODEGRAPH`, `BUNDLER_CODEGRAPH_EXCLUDE` and `BUNDLER_CODEGRAPH_BIN` environment variables
