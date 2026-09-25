# bundler-codegraph

[![GitHub license](https://img.shields.io/github/license/jbox-web/bundler-codegraph.svg)](https://github.com/jbox-web/bundler-codegraph/blob/master/LICENSE)
[![CI](https://github.com/jbox-web/bundler-codegraph/workflows/CI/badge.svg)](https://github.com/jbox-web/bundler-codegraph/actions)
[![Maintainability](https://qlty.sh/gh/jbox-web/projects/bundler-codegraph/maintainability.svg)](https://qlty.sh/gh/jbox-web/projects/bundler-codegraph)
[![Code Coverage](https://qlty.sh/gh/jbox-web/projects/bundler-codegraph/coverage.svg)](https://qlty.sh/gh/jbox-web/projects/bundler-codegraph)

A Bundler plugin that builds a [CodeGraph][codegraph] index inside every gem it
installs.

## Why

Answering *"what does this gem actually do here?"* normally means a grep/read
loop through `.bundle/ruby/*/gems/<gem>/`: guess a filename, read it, follow a
constant into another file, read that one too. Every hop is a round-trip, the
whole file lands in the context window when three methods were needed, and
nothing in that loop can follow a dynamically dispatched call.

[CodeGraph][codegraph] turns a directory into a local SQLite knowledge graph of
symbols, edges and files. Querying it returns the relevant symbols' verbatim
source *and* the call paths between them, in a single round-trip:

```bash
codegraph explore --path .bundle/ruby/4.0.0/gems/rack-3.2.6 "Rack::Session::Cookie"
```

The MCP tool takes the same value as `projectPath`, so an agent gets the same
answer without shelling out.

The catch: the index has to already exist when the question comes up. Running
`codegraph init` by hand on a few hundred gem directories, and again after every
`bundle update`, is not a plan. That is the whole point of this plugin — the
index is a side effect of `bundle install`, and nobody has to think about it.

## Install

### 1. The `codegraph` binary

It must be on `PATH`. Through [mise][mise] and the [jbox-web aqua
registry][aqua-registry]:

```toml
# mise.toml
[settings]
aqua.registries = ["https://github.com/jbox-web/aqua-registry"]

[tools]
"aqua:colbymchenry/codegraph" = "1.5.0"
```

Or straight from npm:

```bash
npm install -g @colbymchenry/codegraph
```

If the binary is missing the plugin turns itself into a no-op rather than
failing the install, so this step can be skipped on machines that do not need
the indexes.

### 2. The plugin

Add it to the `Gemfile` of the project whose dependencies you want indexed:

```ruby
plugin 'bundler-codegraph', git: 'https://github.com/jbox-web/bundler-codegraph.git', branch: 'master'
```

A `plugin` declaration takes the same options as a `gem` one — Bundler's plugin
DSL delegates straight to it — so `github:`, `tag:`, `ref:` and `path:` all
work. Use `path:` when hacking on the plugin itself, since it picks changes up
without a commit:

```ruby
plugin 'bundler-codegraph', path: '/path/to/bundler-codegraph'
```

Bundler installs it into `.bundle/plugin/` on the next `bundle install`. Two
things to know afterwards:

- Bundler records the plugin under the source declared here. Change that source
  — move a `path:` checkout, switch from `path:` to `git:` — and the next
  `bundle install` fails on a `CommandConflict` until you run `bundle plugin
  uninstall bundler-codegraph`.
- A `git:` clone is pinned to the commit resolved at install time, and there is
  no `bundle plugin update`. Uninstalling and reinstalling is how you move it
  forward.

## Usage

Nothing to run: each gem is indexed right after Bundler installs it.

A bundle that is already in place needs one catch-up pass:

```bash
bundle codegraph-index          # index every gem that has none, sync the others
bundle codegraph-index --force  # rebuild all of them
```

Without `--force`, an index already in place goes through `codegraph sync`,
which also completes an index a killed run left partial.

Both walk the *resolved* bundle (`Bundler.definition.specs`, minus `bundler`
itself), not the contents of `.bundle/ruby/*/gems/`. Stale checkouts and older
versions of a gem sitting next to the one in `Gemfile.lock` are left alone, so
an unindexed directory down there is expected rather than a missed gem. Gems
installed from a Git source live in `.bundle/ruby/*/bundler/gems/`, and `path:`
sources are indexed where they sit — add `.codegraph` to the `.gitignore` of any
`path:` source tracked by Git.

## Using the index from an agent

Indexing every gem is only worth it if the agent actually reaches for those
indexes. Two things are needed.

**Wire up the MCP server.** `codegraph install` configures it for Claude Code,
Cursor, Codex CLI, opencode and Hermes Agent (`--target`, `--location`, or
`--print-config <agent>` to just see the snippet). It runs over stdio as
`codegraph serve --mcp` and exposes `codegraph_explore` — relevant symbols'
verbatim source plus the call paths between them — and `codegraph_node`, for one
symbol's caller/callee trail or a line-numbered file read.

Both take a `projectPath`, and the server resolves the nearest `.codegraph/` at
or above it. **That is what makes this plugin useful**: an index dropped inside a
gem directory is queryable from any project, without registering each gem as a
project of its own.

**Tell the agent to use them.** Nothing here changes an agent's default habit of
grepping through vendored sources, so the rule has to be written down. Something
along these lines, in the consuming project's `CLAUDE.md` / `AGENTS.md`:

```markdown
## Dependencies

Every gem of the bundle carries its own CodeGraph index. For a question about a
dependency's code, query that gem's index rather than reading its files:

- `codegraph_explore` with `projectPath` set to the gem directory, e.g.
  `.bundle/ruby/4.0.0/gems/rack-3.2.6`
- or `codegraph explore -p <gem directory> "<symbol or question>"`

Take the version from `Gemfile.lock`: several versions of a gem can sit side by
side on disk, and only the resolved one is indexed. If a gem has no
`.codegraph/` directory, run `bundle codegraph-index` at the project root and
retry.
```

## How it works

`plugins.rb` registers two things with Bundler, and is the only file in the
repository that touches Bundler's plugin API.

**The `after-install` hook.** Bundler emits `GEM_AFTER_INSTALL` once per gem. The
plugin checks the install actually succeeded, then runs `codegraph init <gem
path>`, which drops a `.codegraph/` directory next to the gem's sources. Two
properties of that hook are deliberate:

- *It never raises.* Every outcome — binary missing, no Ruby source, index
  already there, `codegraph` exiting non-zero — comes back as a status symbol
  and is swallowed. An exception raised from a Bundler hook aborts the entire
  `bundle install`, and a failed index is never a good enough reason to break
  someone's install.
- *It never leaves a partial index.* `codegraph init` creates `.codegraph/`
  before it starts indexing, so a run that fails or is interrupted (Ctrl-C
  included) has its `.codegraph/` removed rather than left for the next run to
  mistake for a complete index. `--force` sets the previous index aside and puts
  it back when the rebuild fails.
- *It serializes.* Bundler calls the hook from each of its `BUNDLE_JOBS`
  parallel install workers, and `codegraph` is itself multi-threaded and already
  saturates several cores. Left alone, a cold `bundle install` would start a
  dozen indexers at once. An advisory `flock` on a file in `Dir.tmpdir` keeps it
  to one at a time — and, being filesystem-wide, also covers two `bundle
  install` running side by side.

**The `codegraph-index` command.** The hook only fires for gems Bundler
*actually installs*, which means a bundle already sitting on disk — the usual
case when the plugin is added to an existing project — would never get a single
index. The command is the catch-up pass, and reports a per-gem status so it is
obvious what was skipped and why. It is also the repair pass: it runs
`codegraph sync` on every index already there, which completes one a killed
`bundle install` left partial — something the hook cannot see, since it skips
existing indexes to keep `bundle install` fast.

## Configuration

| Variable | Effect |
| --- | --- |
| `BUNDLER_CODEGRAPH` | `0`, `off`, `false` or `no` disables the plugin entirely |
| `BUNDLER_CODEGRAPH_EXCLUDE` | Comma-separated glob patterns matched against gem names, e.g. `tzinfo-data,rails-*` |
| `BUNDLER_CODEGRAPH_BIN` | Absolute path to the `codegraph` binary when it is not on `PATH` |

There is no *include* list on purpose: restricting a run to a handful of gems is
rare enough that negative globs do the job, and an include list would silently
shrink the coverage a later `bundle install` is expected to produce.

## Cost

Expect an index to weigh roughly **four times the gem's source**: rack 3.2.6 is
528 kB on disk and produces a 2.1 MB index, built in under a second. Scaled to a
real application — a ~400-gem bundle — that is a few minutes for the initial
catch-up pass and somewhere around 600 MB under `.bundle/`. Gems holding no Ruby
source at all are skipped, and the hook skips gems that already carry a
`.codegraph/` directory, so the steady-state cost after the first pass is only
whatever `bundle update` brings in. `bundle codegraph-index` syncs those
existing indexes instead, at a fraction of a second each on a healthy one.

`.bundle/` is usually already git-ignored; `path:` sources are not, hence the
`.gitignore` note above.

## License

MIT — see [LICENSE](LICENSE).

[codegraph]: https://github.com/colbymchenry/codegraph
[mise]: https://mise.jdx.dev
[aqua-registry]: https://github.com/jbox-web/aqua-registry
