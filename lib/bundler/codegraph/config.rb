# frozen_string_literal: true

module Bundler
  module Codegraph

    # Runtime configuration, driven entirely by environment variables so that a
    # single `bundle install` can be run with indexing off without editing a file.
    class Config

      ENV_ENABLED = 'BUNDLER_CODEGRAPH'
      ENV_EXCLUDE = 'BUNDLER_CODEGRAPH_EXCLUDE'
      ENV_BINARY  = 'BUNDLER_CODEGRAPH_BIN'

      DEFAULT_BINARY  = 'codegraph'
      DISABLED_VALUES = %w[0 off false no].freeze

      attr_reader :env, :exclude_patterns, :binary

      # @param env [Hash] environment to read the configuration from
      def initialize(env: ENV)
        @env              = env
        @disabled         = DISABLED_VALUES.include?(env[ENV_ENABLED].to_s.strip.downcase)
        @exclude_patterns = env[ENV_EXCLUDE].to_s.split(',').map(&:strip).reject(&:empty?)
        @binary           = env[ENV_BINARY].to_s.empty? ? DEFAULT_BINARY : env[ENV_BINARY]
      end

      def disabled?
        @disabled
      end

      # @param gem_name [String] name of the gem about to be indexed
      # @return [Boolean] true when the gem matches one of the exclusion globs
      def excluded?(gem_name)
        exclude_patterns.any? { |pattern| File.fnmatch?(pattern, gem_name.to_s) }
      end
    end
  end
end
