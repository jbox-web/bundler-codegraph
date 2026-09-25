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

      def exec(_command_name, args)
        force = args.include?(FORCE_FLAG)

        results = Backfill.new(gem_specs, force: force, sync: true, reporter: method(:report)).call

        Bundler.ui.info("\n#{summary(results)}")
      end

      private

      def gem_specs
        root = Bundler.root
        Bundler.definition.specs.select { |spec| Codegraph.dependency?(spec, root) }
      end

      def report(name, status)
        Bundler.ui.info("#{name}: #{STATUS_LABELS.fetch(status, status)}")
      end

      def summary(results)
        results.map { |status, count| "#{count} #{STATUS_LABELS.fetch(status, status)}" }.join(', ')
      end
    end
  end
end
