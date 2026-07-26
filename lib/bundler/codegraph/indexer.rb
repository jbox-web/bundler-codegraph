# frozen_string_literal: true

require 'fileutils'

module Bundler
  module Codegraph

    # Builds a CodeGraph index for a single gem directory.
    #
    # Never raises: every failure mode is reported as a status symbol, because
    # this runs from a Bundler hook where an exception would abort the whole
    # `bundle install`.
    class Indexer

      INDEX_DIRNAME = '.codegraph'

      attr_reader :path, :name, :config, :force

      # @param path [String] absolute path of the directory to index
      # @param name [String] gem name, used for the exclusion patterns
      # @param config [Config]
      # @param force [Boolean] drop and rebuild an existing index
      def initialize(path, name:, config: Config.new, force: false)
        @path       = path.to_s
        @name       = name.to_s
        @config     = config
        @force      = force
        @executable = nil
      end

      # @return [Symbol] :indexed, :failed, :disabled, :excluded, :missing,
      #   :no_ruby, :already_indexed or :unavailable
      def call
        skipped = skip_reason
        return skipped if skipped

        Lock.synchronize { run }
      rescue StandardError
        :failed
      end

      def indexed?
        Dir.exist?(File.join(path, INDEX_DIRNAME))
      end

      private

      # Ordered cheapest-first: the filesystem walk and the PATH lookup only run
      # once the configuration checks have passed.
      def skip_reason
        config_skip_reason || filesystem_skip_reason
      end

      def config_skip_reason
        return :disabled if config.disabled?
        return :excluded if config.excluded?(name)

        nil
      end

      def filesystem_skip_reason
        return :missing         unless Dir.exist?(path)
        return :already_indexed if indexed? && !force
        return :no_ruby         unless ruby_sources?
        return :unavailable     unless executable

        nil
      end

      # Stops at the first hit instead of materializing the whole file list.
      def ruby_sources?
        Dir.glob(File.join(path, '**', '*.rb')) { |_file| return true }
        false
      end

      def executable
        @executable ||= which(config.binary)
      end

      def which(binary)
        return binary if binary.include?(File::SEPARATOR) && runnable?(binary)

        config.env.fetch('PATH', '').split(File::PATH_SEPARATOR).each do |dir|
          candidate = File.join(dir, binary)
          return candidate if runnable?(candidate)
        end

        nil
      end

      def runnable?(candidate)
        File.file?(candidate) && File.executable?(candidate)
      end

      def run
        FileUtils.rm_rf(File.join(path, INDEX_DIRNAME)) if force
        system(executable, 'init', path, out: File::NULL, err: File::NULL) ? :indexed : :failed
      end
    end
  end
end
