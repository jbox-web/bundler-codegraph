# frozen_string_literal: true

require 'tmpdir'

module Bundler
  module Codegraph

    # Serializes indexing across Bundler's parallel install workers.
    #
    # `codegraph` already saturates several cores on its own, and Bundler runs
    # `after-install` from each worker (see `Bundler::ParallelInstaller#do_install`),
    # so without this lock a cold `bundle install` would spawn BUNDLE_JOBS
    # indexers at once. An advisory file lock also covers the case where several
    # `bundle install` run side by side.
    module Lock

      LOCK_FILENAME = 'bundler-codegraph.lock'

      def self.path
        File.join(Dir.tmpdir, LOCK_FILENAME)
      end

      # Runs the block while holding the exclusive lock. Filesystems without
      # working advisory locks degrade to running unserialized rather than failing.
      def self.synchronize
        File.open(path, File::RDWR | File::CREAT, 0o644) do |file|
          file.flock(File::LOCK_EX)
          return yield
        end
      rescue SystemCallError, NotImplementedError
        yield
      end
    end
  end
end
