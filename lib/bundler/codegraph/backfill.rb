# frozen_string_literal: true

module Bundler
  module Codegraph

    # Indexes a whole set of gem specs, one at a time: the queue
    # `after_install_all` drains at the end of `bundle install`, or the whole
    # resolved bundle for `bundle codegraph-index`.
    class Backfill

      attr_reader :specs, :reporter, :indexer_options

      # @param specs [Enumerable] objects responding to `name` and `full_gem_path`
      # @param reporter [#call, nil] called after each gem with its name, its
      #   status and `Indexer#log_hint`
      # @param indexer_options [Hash] handed to every `Indexer` as is (`config:`,
      #   `force:`, `sync:`, `skip_failed:`), with a single `Config` for them all
      def initialize(specs, reporter: nil, **indexer_options)
        @specs           = specs
        @reporter        = reporter
        @indexer_options = { config: Config.new }.merge(indexer_options)
      end

      # @return [Hash{Symbol => Integer}] number of gems per resulting status
      def call
        specs.each_with_object(Hash.new(0)) do |spec, results|
          name, status, log_hint = index(spec)
          results[status] += 1
          reporter&.call(name, status, log_hint)
        end
      end

      private

      # A spec that cannot even be read counts as a failure of its own, rather
      # than cutting the pass short for every gem after it.
      def index(spec)
        indexer = Indexer.new(spec.full_gem_path, name: spec.name, **indexer_options)
        [spec.name, indexer.call, indexer.log_hint]
      rescue StandardError
        [spec.respond_to?(:name) ? spec.name : spec.to_s, :failed, '']
      end
    end
  end
end
