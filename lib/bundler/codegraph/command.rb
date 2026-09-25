# frozen_string_literal: true

module Bundler
  module Codegraph

    # `bundle codegraph-index [--force]`
    #
    # Indexes every gem of the current bundle, and runs `codegraph sync` on the
    # indexes already there — which also completes one a killed run left
    # partial. Loaded only from `plugins.rb`, so the rest of the gem stays
    # testable without Bundler's plugin API.
    class Command < Bundler::Plugin::API

      FORCE_FLAG = '--force'

      # Labels for the statuses worth reporting; anything else is silent noise.
      STATUS_LABELS = {
        indexed:         'indexed',
        synced:          'synchronized',
        already_indexed: 'already indexed',
        excluded:        'excluded',
        no_ruby:         'no Ruby source',
        missing:         'not installed',
        unavailable:     'codegraph not found',
        disabled:        'disabled',
        failed:          'failed',
      }.freeze

      HELP_FLAGS = %w[--help -h].freeze

      USAGE = <<~USAGE
        Usage: bundle codegraph-index [--force]

        Indexes every gem of the bundle with codegraph, and syncs the indexes already there.

          --force  rebuild every index from scratch
      USAGE

      # Exits non-zero (through a `Bundler::BundlerError`) on an unknown
      # argument, when the binary is missing — before walking the bundle, rather
      # than reporting every gem as `codegraph not found` — and once every gem
      # was tried when any of them failed, so a script can tell. `--help` is
      # what `bundle help codegraph-index` passes.
      def exec(_command_name, args)
        return Bundler.ui.info(USAGE) if args.intersect?(HELP_FLAGS)

        force  = force?(args)
        config = Config.new
        ensure_executable(config)
        Codegraph.warn_untrusted_runtime_dir(Bundler.ui, config)

        results = Backfill.new(gem_specs, config: config, force: force, sync: true, reporter: method(:report)).call
        Bundler.ui.info("\n#{summary(results)}")
        ensure_no_failure(results)
      end

      private

      def force?(args)
        unknown = args - [FORCE_FLAG]
        raise Bundler::InvalidOption, "Unknown option: #{unknown.join(' ')}" unless unknown.empty?

        args.include?(FORCE_FLAG)
      end

      def ensure_executable(config)
        return if config.disabled? || config.executable

        raise Bundler::PluginError, "codegraph not found (#{config.binary})"
      end

      def ensure_no_failure(results)
        failed = results[:failed]
        return if failed.zero?

        raise Bundler::PluginError, "#{failed} gem#{'s' if failed > 1} failed to index"
      end

      def gem_specs
        root = Bundler.root
        Bundler.definition.specs.select { |spec| Codegraph.dependency?(spec, root) }
      end

      def report(name, status, log_hint)
        Bundler.ui.info("#{name}: #{STATUS_LABELS.fetch(status, status)}#{log_hint}")
      end

      def summary(results)
        results.map { |status, count| "#{count} #{STATUS_LABELS.fetch(status, status)}" }.join(', ')
      end
    end
  end
end
