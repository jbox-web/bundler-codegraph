# frozen_string_literal: true

require 'simplecov'
require 'digest'

# Start SimpleCov
SimpleCov.start do
  enable_coverage :branch
  # Count files no spec loads too, so they show up as uncovered instead of
  # silently leaving the denominator. `version.rb` is left out: the gemspec
  # requires it while `bundler/setup` runs, before SimpleCov starts, so it could
  # only ever read as uncovered.
  cover '{lib/**/*.rb,plugins.rb}'
  skip 'lib/bundler/codegraph/version.rb'
  formatter SimpleCov::Formatter::MultiFormatter.new([SimpleCov::Formatter::HTMLFormatter, SimpleCov::Formatter::JSONFormatter])
  skip 'spec/'
end

# Configure RSpec
RSpec.configure do |config|
  config.color = true
  config.fail_fast = false

  config.order = :random
  Kernel.srand config.seed

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # disable monkey patching
  # see: https://relishapp.com/rspec/rspec-core/v/3-8/docs/configuration/zero-monkey-patching-mode
  config.disable_monkey_patching!

  config.raise_errors_for_deprecations!
end

# Build a fake `codegraph` executable that records its arguments in a log file
# and, on `init`, creates the `.codegraph` directory and its database (even when
# told to fail, like the real binary does), so the indexer can be exercised end
# to end without the real binary.
#
# `stderr` is written to the error stream before exiting. `probe_stdin` makes
# `init` read one line from its standard input and log it, which is how a spec
# can tell whether the indexer hands its own stdin over. `hang` makes `init`
# write its pid to `<log>.pid` and wait; `self_kill` makes it die of SIGKILL.
# rubocop:disable-next Metrics/ParameterLists
def build_fake_codegraph(dir, log:, exit_status: 0, stderr: nil, probe_stdin: false, hang: false, self_kill: false)
  path = File.join(dir, 'codegraph')
  File.write(path, <<~SHELL)
    #!/bin/sh
    echo "$@" >> "#{log}"
    if [ "$1" = "init" ]; then
      mkdir -p "$2/.codegraph" && : > "$2/.codegraph/codegraph.db"
      #{probe_stdin ? %(IFS= read -r line && echo "stdin:$line" >> "#{log}") : ':'}
      #{hang ? %(echo $$ > "#{log}.pid" && exec sleep 30) : ':'}
      #{self_kill ? 'kill -KILL $$' : ':'}
    fi
    #{stderr ? %(echo "#{stderr}" >&2) : ':'}
    exit #{exit_status}
  SHELL
  File.chmod(0o755, path)
  path
end

RSpec::Matchers.define_negated_matcher :not_change, :change

# Where ErrorLog keeps the log of a gem directory: `<basename>-<digest>.log`,
# the digest of the full path telling apart two directories of the same name.
def error_log_for(root, gem_path)
  digest = Digest::SHA256.hexdigest(gem_path)[0, 12]
  File.join(root, "bundler-codegraph-#{Process.uid}", "#{File.basename(gem_path)}-#{digest}.log")
end

# Load our gem
require 'bundler/codegraph'
