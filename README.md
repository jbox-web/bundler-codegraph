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
plugin 'bundler-codegraph'
```

That pulls the released gem from RubyGems.org. To follow unreleased changes,
point it at the repository instead:

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

Bundler installs it into `.bundle/plugin/` on the next `bundle install`.

**Every update of the plugin goes through an uninstall.** Bundler reinstalls a
plugin whenever its path changes — a new release, a new commit fetched by
`bundle update` on a `git:` source, a moved `path:` checkout, a switch from one
source to another — but registers the new copy without removing the old one,
and refuses the `codegraph-index` command the old copy still holds:

```
Failed to install plugin `bundler-codegraph`, due to Bundler::Plugin::Index::CommandConflict (Command(s) `codegraph-index` declared by bundler-codegraph are already registered.)
```

That is Bundler's doing (checked on 4.0.17), and it hits any plugin that
declares a command. Uninstall first, then install again:

```bash
bundle plugin uninstall bundler-codegraph && bundle install
```

There is no `bundle plugin update`: this is also how a `git:` clone, pinned to
the commit resolved at install time, moves forward.

## Usage

Nothing to run: every gem of the bundle is indexed at the end of each
`bundle install`.

A bundle that is already in place needs one catch-up pass:

```bash
bundle codegraph-index          # index every gem that has none, sync the others
bundle codegraph-index --force  # rebuild all of them
```

Without `--force`, an index already in place goes through `codegraph sync`,
which also completes an index a killed run left partial.

The command exits non-zero on an unknown argument, when the `codegraph` binary
cannot be found (checked before walking the bundle), and — after trying every
gem — when any of them failed to index, so a script or a CI job can tell.
`bundle codegraph-index --help` (or `bundle help codegraph-index`) prints its
usage.

Both walk the *resolved* bundle (`Bundler.definition.specs`, minus `bundler`
itself and minus the project's own gemspec — a gem project declaring `gemspec`
is not one of its dependencies), not the contents of `.bundle/ruby/*/gems/`.
Stale checkouts and older versions of a gem sitting next to the one in
`Gemfile.lock` are left alone, so an unindexed directory down there is expected
rather than a missed gem. Gems installed from a Git source live in
`.bundle/ruby/*/bundler/gems/`, and `path:` sources are indexed where they sit.
codegraph drops a `.gitignore` inside `.codegraph/` that ignores everything but
itself, so the database never shows up in Git; that `.gitignore` itself still
does, as an untracked file — add `.codegraph` to the `.gitignore` of any `path:`
source tracked by Git to keep its status clean.

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

`plugins.rb` registers two hooks and a command with Bundler, and is the only
file in the repository that touches Bundler's plugin API.

**The install hooks.** Bundler emits `GEM_AFTER_INSTALL` once per gem, from the
install worker that handled it — on Bundler 4 (checked on 4.0.17) for every gem
of the bundle on every `bundle install`, whether it was just installed or
already there. The plugin checks the install succeeded and only queues the gem:
indexing from the worker would hold it for as long as `codegraph` runs and stall
the rest of the install. Once everything is installed Bundler emits
`GEM_AFTER_INSTALL_ALL`, and the plugin runs `codegraph init <gem path>` on each
queued gem, one at a time, which drops a `.codegraph/` directory next to the
gem's sources. A `bundle install` that fails never emits that second hook, so
the gems it did install stay unindexed until `bundle codegraph-index` runs.
Each gem it indexes prints a `bundler-codegraph: indexed <gem>` line, so a cold
install that spends minutes in `codegraph` after Bundler is done does not look
hung. Three properties of that indexing pass are deliberate:

- *It never raises.* Every outcome — binary missing, no Ruby source, index
  already there, `codegraph` exiting non-zero — comes back as a status symbol
  and is swallowed. An exception raised from a Bundler hook aborts the entire
  `bundle install`, and a failed index is never a good enough reason to break
  someone's install. A gem `codegraph` fails on still gets a one-line warning,
  pointing at its error output, kept in
  `bundler-codegraph-<uid>/<gem directory>-<digest>.log` (`rack-3.2.6-…log`) under
  `Dir.tmpdir` until a later run succeeds. The hook does not retry that gem on
  the next `bundle install` — it would pay the same failure every time — and
  says so in a `skipped` line, until a new version lands in a new directory,
  `bundle codegraph-index` retries it, or the system purges its temporary
  directory (macOS does on its own, Linux usually at boot). A `path:` source
  keeps its directory: after fixing it, run `bundle codegraph-index`. An interrupted run
  (codegraph is stopped before the cleanup, killed if it ignores TERM), a `codegraph` killed by a signal
  (the OOM killer) or one that could not even start is not a failure: no log is
  kept, and the gem is tried again next time.
- *It never leaves a partial index.* An index is a `.codegraph/codegraph.db`,
  and `codegraph init` creates `.codegraph/` before it starts indexing, so a run
  that fails or is interrupted (Ctrl-C included) has its `.codegraph/` removed
  rather than left for the next run to mistake for a complete index; a bare
  `.codegraph/` without its database is such a leftover, and is rebuilt.
  `--force` sets the previous index aside and puts it back when the rebuild
  fails — or on the next run, when the rebuild was killed outright.
- *It serializes.* `codegraph` is itself multi-threaded and already saturates
  several cores, so the queue is indexed one gem at a time, and an advisory
  `flock` keeps two `bundle install` (or a `bundle install` and a `bundle
  codegraph-index`) running side by side from indexing at once. The lock file
  sits in a private per-user directory, `bundler-codegraph-<uid>` under
  `Dir.tmpdir`, created `0700` (and closed again if it is yours but was left
  open); when that path is not a directory owned by you — someone planted it
  in a shared `/tmp` — indexing runs unserialized and without error logs
  rather than trusting it, and both the hook and `bundle codegraph-index` say
  so.

**The `codegraph-index` command.** The catch-up pass for whatever the hooks
missed — a failed `bundle install`, an index deleted by hand — and it reports a
per-gem status so it is obvious what was skipped and why. It is also the repair
pass: it runs `codegraph sync` on every index already there, which completes
one a killed `bundle install` left partial — something the hook cannot see,
since it skips existing indexes to keep `bundle install` fast — and it retries
the gems the hook stopped retrying after a failure.

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
catch-up pass and somewhere around 600 MB next to the gems. Gems holding no Ruby
source at all are skipped, and the hook skips gems that already carry an index
(`.codegraph/codegraph.db`), so the steady-state cost after the first pass is
only whatever `bundle update` brings in. `bundle codegraph-index` syncs those
existing indexes instead, at a fraction of a second each on a healthy one.

An index lands next to its gem, wherever Bundler installed it. With a
project-local `BUNDLE_PATH` (`bundle config set --local path .bundle`, as the
examples above assume) that is the project's `.bundle/`. Without one, gems —
and so their indexes — live in the Ruby installation's shared `GEM_HOME`, used
by every project on that Ruby: the 600 MB land there, an index built for one
project serves the others, and `bundle codegraph-index --force` in one project
rebuilds them for all. Set `BUNDLE_PATH` to keep the indexes per project.

`.bundle/` is usually already git-ignored; `path:` sources are not, hence the
`.gitignore` note above.

## License

MIT — see [LICENSE](LICENSE).

[codegraph]: https://github.com/colbymchenry/codegraph
[mise]: https://mise.jdx.dev
[aqua-registry]: https://github.com/jbox-web/aqua-registry
