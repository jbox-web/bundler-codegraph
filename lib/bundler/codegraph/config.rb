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
        @env                 = env
        @disabled            = DISABLED_VALUES.include?(env[ENV_ENABLED].to_s.strip.downcase)
        @exclude_patterns    = env[ENV_EXCLUDE].to_s.split(',').map(&:strip).reject(&:empty?)
        @binary              = env[ENV_BINARY].to_s.empty? ? DEFAULT_BINARY : env[ENV_BINARY]
        @executable          = nil
        @executable_resolved = false
      end

      # Resolved lazily, once: the `PATH` lookup only runs when something
      # actually needs the binary.
      #
      # @return [String, nil] path of the codegraph executable, nil when not found
      def executable
        return @executable if @executable_resolved

        @executable_resolved = true
        @executable = which(binary)
      end

      def disabled?
        @disabled
      end

      # @param gem_name [String] name of the gem about to be indexed
      # @return [Boolean] true when the gem matches one of the exclusion globs
      def excluded?(gem_name)
        exclude_patterns.any? { |pattern| File.fnmatch?(pattern, gem_name.to_s) }
      end

      private

      # A name holding a separator is a path: used as is, never looked up on
      # PATH. An empty PATH entry stands for the current directory, as in POSIX
      # — `File.join('', name)` would make it the filesystem root.
      def which(name)
        return (runnable?(name) ? name : nil) if name.include?(File::SEPARATOR)

        env.fetch('PATH', '').split(File::PATH_SEPARATOR, -1).each do |dir|
          candidate = File.join(dir.empty? ? '.' : dir, name)
          return candidate if runnable?(candidate)
        end

        nil
      end

      def runnable?(candidate)
        File.file?(candidate) && File.executable?(candidate)
      end
    end
  end
end
