# frozen_string_literal: true

require 'digest'
require 'fileutils'

module Bundler
  module Codegraph

    # codegraph's error output for one gem, kept in the runtime directory for
    # as long as the last run on that gem failed.
    #
    # The log starts with the directory it is about, is written under a
    # temporary name while codegraph runs, and only takes its own name once the
    # run failed: a log naming a directory means codegraph failed on it and
    # nothing retried it since — never that a run is still going. A new version
    # of the gem is a new directory.
    class ErrorLog

      # Named after the gem directory and a digest of its full path
      # (`rack-3.2.6-<digest>.log`): two directories of the same name — the
      # same version in two projects' `.bundle/`, two `path:` sources called
      # `admin` — keep a log each, instead of erasing each other's on every run.
      #
      # @param gem_path [String] directory codegraph runs on
      # @return [String, nil] nil when the runtime directory cannot be trusted
      def self.path(gem_path)
        dir = RuntimeDir.path
        dir && File.join(dir, "#{File.basename(gem_path)}-#{::Digest::SHA256.hexdigest(gem_path)[0, 12]}.log")
      end

      attr_reader :path, :gem_path

      # @param gem_path [String] directory codegraph runs on
      def initialize(gem_path)
        @path     = self.class.path(gem_path)
        @gem_path = gem_path
        @kept     = false
        @logged   = false
      end

      # Whether the last `capture` kept a log — the only log a failure message
      # may point at: one found on disk could predate this attempt, or belong
      # to another process working on another version of the gem.
      def kept?
        @kept
      end

      # Where to find codegraph's error output, as a suffix for a failure
      # message; empty unless this attempt kept a log.
      #
      # @return [String]
      def hint
        kept? ? ", see #{path}" : ''
      end

      def failed_before?
        return false unless path && File.exist?(path)

        File.foreach(path).first&.chomp == gem_path
      end

      def discard
        FileUtils.rm_f(path) if path
      end

      # Yields the stream codegraph's stderr should go to, and keeps the log
      # only when the block returns a failure. An exception — `Interrupt`
      # included — drops it too: codegraph did not fail, it was stopped, and a
      # kept log would stop the hook from ever retrying the gem.
      #
      # Only an explicit `false` is a codegraph failure: `nil` means it could
      # not even be started. A log that cannot be opened (full disk) must not
      # cost the index either, so codegraph then runs without one.
      #
      # @return the block's value
      def capture(&)
        @kept = false
        return yield(File::NULL) unless path

        succeeded = write(&)
        @kept = succeeded == false && @logged && publish
        succeeded
      ensure
        FileUtils.rm_f(partial_path) if path
      end

      private

      def partial_path
        "#{path}.part"
      end

      # The header goes in first. A log that cannot be opened or written (full
      # disk) falls back to running codegraph without one — and is never
      # published, empty, as the log of a failure; an error raised by the block
      # itself propagates, rather than running codegraph twice.
      def write
        @logged = false
        File.open(partial_path, 'w', 0o600) do |file|
          file.puts(gem_path)
          file.flush
          @logged = true
          return yield file
        end
      rescue SystemCallError
        raise if @logged

        yield File::NULL
      end

      def publish
        File.rename(partial_path, path)
        true
      rescue SystemCallError
        false
      end
    end
  end
end
