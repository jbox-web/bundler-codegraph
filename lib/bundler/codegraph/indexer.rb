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

      attr_reader :path, :name, :config, :force, :sync, :skip_failed

      # @param path [String] absolute path of the directory to index
      # @param name [String] gem name, used for the exclusion patterns
      # @param config [Config]
      # @param force [Boolean] drop and rebuild an existing index
      # @param sync [Boolean] run `codegraph sync` on an existing index instead
      #   of skipping it, which also completes an index a killed run left behind
      # @param skip_failed [Boolean] skip a directory codegraph already failed
      #   on, as long as its error log is there
      # rubocop:disable-next Metrics/ParameterLists
      def initialize(path, name:, config: Config.new, force: false, sync: false, skip_failed: false)
        @path        = path.to_s
        @name        = name.to_s
        @config      = config
        @force       = force
        @sync        = sync
        @skip_failed = skip_failed
        @error_log   = nil
      end

      # @return [Symbol] :indexed, :synced, :failed, :disabled, :excluded,
      #   :missing, :failed_before, :no_ruby, :already_indexed or :unavailable
      def call
        skipped = skip_reason
        return skipped if skipped

        Lock.synchronize do
          error_log.discard
          run
        end
      rescue StandardError
        :failed
      end

      # Where to find codegraph's error output after `call`, as a suffix for a
      # failure message (see `ErrorLog#hint`).
      #
      # @return [String]
      def log_hint
        @error_log ? @error_log.hint : ''
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
        return :failed_before   if skip_failed && error_log.failed_before?
        return :no_ruby         unless ruby_sources?

        nil
      end

      # An index this run leaves alone: present, neither forced nor synced, and
      # not sitting next to the backup a killed `--force` rebuild left behind.
      def keep_index?
        indexed? && !force && !sync && !Dir.exist?(backup_path)
      end

      # Stops at the first hit instead of materializing the whole file list.
      # The path goes through `base:`, never into the pattern: a checkout under
      # a directory named `client [2026]` would otherwise match nothing.
      def ruby_sources?
        Dir.glob('**/*.rb', base: path) { |_file| return true }
        false
      end

      def executable
        config.executable
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
      # stderr goes to the gem's `ErrorLog`, kept only when the run fails.
      def codegraph(command)
        error_log.capture { |stderr| Subprocess.run([executable, command, path], stderr) }
      end

      # The log of an earlier run is discarded once this one holds the lock
      # (see `call`) — never earlier, where it could be another process's log
      # still being written — so a log that exists afterwards always holds codegraph's
      # output from this run — never a stale one, when this run failed before
      # codegraph even ran.
      def error_log
        @error_log ||= ErrorLog.new(path)
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
