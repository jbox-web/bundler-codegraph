# bundler-codegraph

[![GitHub license](https://img.shields.io/github/license/jbox-web/bundler-codegraph.svg)](https://github.com/jbox-web/bundler-codegraph/blob/master/LICENSE)
[![CI](https://github.com/jbox-web/bundler-codegraph/workflows/CI/badge.svg)](https://github.com/jbox-web/bundler-codegraph/actions)
[![Maintainability](https://qlty.sh/gh/jbox-web/projects/bundler-codegraph/maintainability.svg)](https://qlty.sh/gh/jbox-web/projects/bundler-codegraph)
[![Code Coverage](https://qlty.sh/gh/jbox-web/projects/bundler-codegraph/coverage.svg)](https://qlty.sh/gh/jbox-web/projects/bundler-codegraph)

A Bundler plugin that builds a CodeGraph index inside every gem it installs.

Reading a dependency's source usually means a grep/read loop through
`.bundle/ruby/*/gems/<gem>/`. With an index sitting in the gem directory, the
same question is one call:

```bash
codegraph explore --path .bundle/ruby/4.0.0/gems/rack-3.2.6 "Rack::Session::Cookie"
```

The MCP tool takes the same argument as `projectPath`.

## Install

Add it to the `Gemfile` of the project whose dependencies you want indexed:

```ruby
plugin 'bundler-codegraph', path: '/path/to/bundler-codegraph'
```

Bundler installs the plugin into `.bundle/plugin/` on the next `bundle install`.
The `codegraph` binary must be on `PATH`; when it is missing the plugin turns
itself into a no-op rather than failing the install.

## Usage

Nothing to run: each gem is indexed right after Bundler installs it.

The hook only fires for gems that are *actually installed*, so a bundle that is
already in place needs one catch-up pass:

```bash
bundle codegraph-index          # index every gem of the bundle that has none
bundle codegraph-index --force  # rebuild all of them
```

Both walk the *resolved* bundle (`Bundler.definition.specs`, minus `bundler`
itself), not the contents of `.bundle/ruby/*/gems/`. Stale checkouts and older
versions of a gem sitting next to the one in `Gemfile.lock` are left alone, so
an unindexed directory down there is expected rather than a missed gem. Gems
installed from a Git source live in `.bundle/ruby/*/bundler/gems/`, and `path:`
sources are indexed where they sit — add `.codegraph` to the `.gitignore` of any
`path:` source tracked by Git.

## Configuration

| Variable | Effect |
| --- | --- |
| `BUNDLER_CODEGRAPH` | `0`, `off`, `false` or `no` disables the plugin entirely |
| `BUNDLER_CODEGRAPH_EXCLUDE` | Comma-separated glob patterns matched against gem names, e.g. `tzinfo-data,rails-*` |
| `BUNDLER_CODEGRAPH_BIN` | Absolute path to the `codegraph` binary when it is not on `PATH` |

## Notes

- Indexing is serialized through an advisory file lock. `codegraph` is already
  multi-threaded, and Bundler fires `after-install` from each of its parallel
  install workers, so without the lock a cold `bundle install` would run
  `BUNDLE_JOBS` indexers at once.
- Gems holding no Ruby source are skipped, as are gems that already carry a
  `.codegraph/` directory.
- Expect the index to weigh roughly four times the gem's source.

## License

MIT — see [LICENSE](LICENSE).
