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

      INDEX_DIRNAME  = '.codegraph'
      DATABASE_NAME  = 'codegraph.db'
      BACKUP_DIRNAME = '.codegraph.bundler-codegraph-backup'

      attr_reader :path, :name, :config, :force, :sync

      # @param path [String] absolute path of the directory to index
      # @param name [String] gem name, used for the exclusion patterns
      # @param config [Config]
      # @param force [Boolean] drop and rebuild an existing index
      # @param sync [Boolean] run `codegraph sync` on an existing index instead
      #   of skipping it, which also completes an index a killed run left behind
      def initialize(path, name:, config: Config.new, force: false, sync: false)
        @path       = path.to_s
        @name       = name.to_s
        @config     = config
        @force      = force
        @sync       = sync
        @executable = nil
      end

      # @return [Symbol] :indexed, :synced, :failed, :disabled, :excluded,
      #   :missing, :no_ruby, :already_indexed or :unavailable
      def call
        skipped = skip_reason
        return skipped if skipped

        Lock.synchronize { run }
      rescue StandardError
        :failed
      end

      # Same criterion as codegraph itself: a `.codegraph/` directory without
      # its database is a leftover, not an index.
      def indexed?
        File.exist?(File.join(index_path, DATABASE_NAME))
      end

      private

      # Ordered cheapest-first: configuration, then single stats, then the PATH
      # lookup (done once per Config), and the walk of the gem's tree last.
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
        return :already_indexed if keep_index?
        return :unavailable     unless executable
        return :no_ruby         unless ruby_sources?

        nil
      end

      # An index this run leaves alone: present, neither forced nor synced, and
      # not sitting next to the backup a killed `--force` rebuild left behind.
      def keep_index?
        indexed? && !force && !sync && !Dir.exist?(backup_path)
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

      # Checks for an index again: another process may have built it while this
      # one waited for the lock.
      #
      # A backup only outlives a `--force` rebuild that never reached its
      # `ensure` (SIGKILL, OOM): whatever `.codegraph/` holds then is that
      # unfinished rebuild, and the backup is the index to keep.
      def run
        restore_backup
        return build unless indexed?
        return rebuild if force

        sync ? refresh : :already_indexed
      end

      # `codegraph init` creates `.codegraph/` before it starts indexing, so a
      # failed or interrupted run leaves a partial index behind that the next
      # run would take for a complete one. Whatever is there when the build does
      # not succeed is therefore removed, a stale leftover included.
      def build
        FileUtils.rm_rf(index_path)
        succeeded = codegraph('init')
        succeeded ? :indexed : :failed
      ensure
        FileUtils.rm_rf(index_path) unless succeeded
      end

      # The previous index is set aside rather than deleted, and put back when
      # the rebuild does not succeed.
      def rebuild
        FileUtils.rm_rf(backup_path)
        File.rename(index_path, backup_path)
        status = build
      ensure
        status == :indexed ? FileUtils.rm_rf(backup_path) : restore_backup
      end

      def restore_backup
        return unless Dir.exist?(backup_path)

        FileUtils.rm_rf(index_path)
        File.rename(backup_path, index_path)
      end

      def refresh
        codegraph('sync') ? :synced : :failed
      end

      # stdin is closed off too: codegraph prompts on it in some setups (live
      # watching disabled, a Git checkout), and with its output going to
      # /dev/null the question would be invisible and `bundle install` would
      # hang on it. At EOF the prompt is cancelled and codegraph moves on.
      def codegraph(command)
        system(executable, command, path, in: File::NULL, out: File::NULL, err: File::NULL)
      end

      def index_path
        File.join(path, INDEX_DIRNAME)
      end

      def backup_path
        File.join(path, BACKUP_DIRNAME)
      end
    end
  end
end
