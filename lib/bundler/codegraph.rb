# frozen_string_literal: true

require_relative 'codegraph/version'
require_relative 'codegraph/config'
require_relative 'codegraph/runtime_dir'
require_relative 'codegraph/error_log'
require_relative 'codegraph/lock'
require_relative 'codegraph/subprocess'
require_relative 'codegraph/indexer'
require_relative 'codegraph/backfill'

module Bundler

  # Bundler plugin building a CodeGraph index inside every gem it installs, so
  # that an agent can query a dependency's source through `codegraph explore
  # --path <gem>` instead of reading its files by hand.
  module Codegraph

    # Specs queued by `after_install`, drained by `after_install_all`. A
    # `Thread::Queue` because Bundler fires `after-install` from each of its
    # parallel install workers.
    @pending = Queue.new

    class << self
      attr_reader :pending
    end

    # Entry point wired to Bundler's `after-install` hook, which fires from the
    # install workers themselves. Indexing there would hold a worker for as long
    # as `codegraph` runs, and stall the rest of the install behind it: the gem
    # is only queued, and `after_install_all` indexes the queue once installing
    # is over.
    #
    # Swallows everything: the hook also fires for failed installs, and a broken
    # index must never be the reason a `bundle install` aborts.
    #
    # @param spec_install [Bundler::ParallelInstaller::SpecInstallation]
    # @param root [Pathname, String, nil] root of the project being installed,
    #   `Bundler.root` by default — resolved in the body, where the rescue
    #   covers it, never as a keyword default, which is evaluated outside it
    # @return [nil]
    def self.after_install(spec_install, root: nil)
      return unless spec_install.respond_to?(:installed?) && spec_install.installed?

      spec = spec_install.spec
      pending << spec if dependency?(spec, root || Bundler.root)
      nil
    rescue StandardError
      nil
    end

    # Entry point wired to Bundler's `after-install-all` hook, fired once every
    # gem is installed — and not at all when the install fails, in which case
    # `bundle codegraph-index` picks up whatever was left unindexed.
    #
    # Swallows everything, for the same reason as `after_install`, but warns
    # about each gem that failed to index, pointing at codegraph's error output.
    #
    # @param config [Config, nil] read from the environment by default
    # @param shell [#warn, nil] Bundler's UI by default; both are resolved in
    #   the body, where the rescue covers them
    # @return [Hash{Symbol => Integer}, nil] number of gems per resulting status
    def self.after_install_all(config: nil, shell: nil)
      config ||= Config.new
      shell  ||= Bundler.ui
      specs = []
      specs << pending.pop until pending.empty?
      warn_untrusted_runtime_dir(shell, config) unless specs.empty?
      # Bundler fires `after-install` for every gem on every `bundle install`:
      # a gem codegraph fails on is not retried each time, only once it changes
      # or when `bundle codegraph-index` runs.
      Backfill.new(specs, config: config, skip_failed: true, reporter: reporter_for(shell)).call
    rescue StandardError
      nil
    end

    # One line per gem actually indexed — a cold install can spend minutes in
    # codegraph after Bundler is done — one per gem skipped after an earlier
    # failure, so it is never left unindexed without a word, and a warning
    # per new failure. Printing may fail (`bundle install | head` closes the
    # pipe); that must not cost the rest of the queue.
    def self.reporter_for(shell)
      lambda do |name, status, log_hint|
        report(shell, name, status, log_hint)
      rescue StandardError
        nil
      end
    end
    private_class_method :reporter_for

    def self.report(shell, name, status, log_hint)
      case status
      when :indexed then shell.info("bundler-codegraph: indexed #{name}")
      when :failed_before
        shell.info("bundler-codegraph: skipped #{name}, codegraph failed on it before; " \
                   '`bundle codegraph-index` retries it')
      when :failed then shell.warn("bundler-codegraph: indexing #{name} failed#{log_hint}")
      end
    end
    private_class_method :report

    # Without a trusted runtime directory the lock and the error logs are both
    # off; say so once rather than let it pass unnoticed — as long as there is
    # any indexing to run at all.
    def self.warn_untrusted_runtime_dir(shell, config)
      return if config.disabled? || !config.executable || RuntimeDir.path

      shell.warn("bundler-codegraph: #{RuntimeDir.candidate} is not a private directory, " \
                 'so indexing runs unserialized and without error logs')
    end

    # Whether a spec of the bundle is a dependency worth indexing. `bundler`
    # itself lives in the Ruby installation, outside the bundle. A project
    # declaring `gemspec` gets its own spec back as a `path:` source rooted at
    # the project directory, which is the project, not a dependency: it is
    # told by its `Bundler::Source::Gemspec` source, since the Gemfile need not
    # sit at the root (Appraisal's `gemfiles/*.gemfile` use `gemspec path:
    # '../'`), and by its path for specs that carry no source.
    #
    # @param spec [#name, #full_gem_path]
    # @param root [Pathname, String] root of the project
    def self.dependency?(spec, root)
      return false if spec.name == 'bundler' || own_gemspec?(spec)

      File.expand_path(spec.full_gem_path) != File.expand_path(root.to_s)
    end

    def self.own_gemspec?(spec)
      defined?(Bundler::Source::Gemspec) && spec.respond_to?(:source) && spec.source.is_a?(Bundler::Source::Gemspec)
    end
    private_class_method :own_gemspec?
  end
end
