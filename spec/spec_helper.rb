# frozen_string_literal: true

require 'simplecov'

# Start SimpleCov
#
# The JSON report is what the CI publishes to qlty; `JSONFormatter` ships with
# simplecov itself since 1.0, so the `simplecov_json_formatter` gem is not needed.
SimpleCov.start do
  enable_coverage :branch
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
# and creates the `.codegraph` directory, so the indexer can be exercised end to
# end without the real binary.
def build_fake_codegraph(dir, log:, exit_status: 0)
  path = File.join(dir, 'codegraph')
  File.write(path, <<~SHELL)
    #!/bin/sh
    echo "$@" >> "#{log}"
    if [ "$1" = "init" ]; then mkdir -p "$2/.codegraph"; fi
    exit #{exit_status}
  SHELL
  File.chmod(0o755, path)
  path
end

# Load our gem
require 'bundler/codegraph'
