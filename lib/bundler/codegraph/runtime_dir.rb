# frozen_string_literal: true

require 'tmpdir'

module Bundler
  module Codegraph

    # A private directory for the plugin's runtime files, one per user under
    # `Dir.tmpdir`.
    #
    # On Linux `Dir.tmpdir` is the shared `/tmp`, where a fixed file name lets
    # another user create it first — and then either hold the lock forever or
    # leave it unopenable. The directory is created 0700 and only trusted when
    # it is a real directory (not a symlink), owned by the current user and
    # closed to everyone else; callers degrade gracefully when it is not.
    module RuntimeDir

      # @return [String] where the directory lives, trusted or not
      def self.candidate
        File.join(Dir.tmpdir, "bundler-codegraph-#{Process.uid}")
      end

      # @return [String, nil] the directory, nil when it cannot be trusted
      def self.path
        dir = candidate
        create(dir)
        trusted?(dir) ? dir : nil
      rescue SystemCallError
        nil
      end

      # A directory already there and ours — a real directory, not a symlink
      # — is closed to others if it was left open (a umask, another tool):
      # otherwise it would stay untrusted, and the lock and logs off, for good.
      def self.create(dir)
        Dir.mkdir(dir, 0o700)
      rescue Errno::EEXIST
        stat = File.lstat(dir)
        File.chmod(0o700, dir) if stat.directory? && stat.uid == Process.uid
      end
      private_class_method :create

      # Owned by `Process.uid`, the same id the directory is named after —
      # `File::Stat#owned?` compares with the effective uid instead.
      def self.trusted?(dir)
        stat = File.lstat(dir)
        stat.directory? && stat.uid == Process.uid && stat.mode.nobits?(0o077)
      end
      private_class_method :trusted?
    end
  end
end
