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

      def self.path
        File.join(Dir.tmpdir, LOCK_FILENAME)
      end

      # Runs the block while holding the exclusive lock. Filesystems without
      # working advisory locks degrade to running unserialized rather than failing.
      #
      # Only opening and locking may fall back: an error raised by the block
      # itself propagates, rather than running the block a second time, unlocked.
      def self.synchronize
        locked = false
        File.open(path, File::RDWR | File::CREAT, 0o644) do |file|
          file.flock(File::LOCK_EX)
          locked = true
          return yield
        end
      rescue SystemCallError, NotImplementedError
        raise if locked

        yield
      end
    end
  end
end
