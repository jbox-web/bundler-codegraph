# frozen_string_literal: true

require 'tmpdir'

module Bundler
  module Codegraph

    # Serializes indexing across processes.
    #
    # `codegraph` already saturates several cores on its own. Within one
    # `bundle install` the queue is drained one gem at a time; this advisory
    # file lock covers several `bundle install` (or a `bundle codegraph-index`)
    # running side by side.
    module Lock

      LOCK_FILENAME = 'bundler-codegraph.lock'

      # @return [String, nil] nil when the runtime directory cannot be trusted
      def self.path
        dir = RuntimeDir.path
        dir && File.join(dir, LOCK_FILENAME)
      end

      # Runs the block while holding the exclusive lock. An untrusted runtime
      # directory, or a filesystem without working advisory locks, degrades to
      # running unserialized rather than failing.
      #
      # Only opening and locking may fall back: an error raised by the block
      # itself propagates, rather than running the block a second time, unlocked.
      def self.synchronize(&)
        lock_path = path
        lock_path ? with_lock(lock_path, &) : yield
      end

      def self.with_lock(lock_path)
        locked = false
        File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |file|
          file.flock(File::LOCK_EX)
          locked = true
          return yield
        end
      rescue SystemCallError, NotImplementedError
        raise if locked

        yield
      end
      private_class_method :with_lock
    end
  end
end
