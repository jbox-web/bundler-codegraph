# frozen_string_literal: true

module Bundler
  module Codegraph

    # Indexes a whole set of gem specs, one at a time.
    #
    # The `after-install` hook only fires for gems Bundler actually installs, so
    # a bundle that is already installed would never get an index. This is what
    # `bundle codegraph-index` runs to catch up.
    class Backfill

      attr_reader :specs, :config, :force, :sync, :reporter

      # @param specs [Enumerable] objects responding to `name` and `full_gem_path`
      # @param config [Config]
      # @param force [Boolean] rebuild indexes that already exist
      # @param sync [Boolean] run `codegraph sync` on indexes that already exist
      # @param reporter [#call, nil] called with (name, status) after each gem
      def initialize(specs, config: Config.new, force: false, sync: false, reporter: nil)
        @specs    = specs
        @config   = config
        @force    = force
        @sync     = sync
        @reporter = reporter
      end

      # @return [Hash{Symbol => Integer}] number of gems per resulting status
      def call
        specs.each_with_object(Hash.new(0)) do |spec, results|
          status = index(spec)
          results[status] += 1
          reporter&.call(spec.name, status)
        end
      end

      private

      def index(spec)
        Indexer.new(spec.full_gem_path, name: spec.name, config: config, force: force, sync: sync).call
      end
    end
  end
end
