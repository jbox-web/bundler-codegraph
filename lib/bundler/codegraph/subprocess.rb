# frozen_string_literal: true

module Bundler
  module Codegraph

    # Runs codegraph as a child process, stdin and stdout closed off.
    #
    # `Kernel#system` would leave the child running when this process alone
    # is interrupted (SIGTERM to Ruby, not its process group): the cleanup that
    # follows — removing a partial index, releasing the lock — would then happen
    # under a live codegraph. The child is stopped and reaped first.
    module Subprocess

      # How long a child gets to exit on TERM before it is killed.
      STOP_TIMEOUT = 5

      # @param argv [Array<String>] command line
      # @param stderr [IO, String] where the child's error output goes
      # @return [Boolean, nil] like `system`, except that a child killed by a
      #   signal (the OOM killer) gives nil, as one that cannot be started: it
      #   did not fail, it was stopped
      def self.run(argv, stderr)
        pid = Process.spawn(*argv, in: File::NULL, out: File::NULL, err: stderr)
        status = Process.wait2(pid).last
        pid = nil
        status.success? || (status.signaled? ? nil : false)
      rescue SystemCallError
        nil
      ensure
        stop(pid) if pid
      end

      # TERM first, KILL once STOP_TIMEOUT is over: a child that ignores TERM
      # must not hang `bundle install` in an `ensure`. A child already reaped
      # (the interrupt landed right after `wait2`) is never signalled, as its
      # pid may have been reused.
      def self.stop(pid)
        return if reaped?(pid)

        Process.kill('TERM', pid)
        return if exited_within?(pid, STOP_TIMEOUT)

        Process.kill('KILL', pid)
        Process.wait(pid)
      rescue SystemCallError
        nil
      end
      private_class_method :stop

      def self.reaped?(pid)
        !Process.wait(pid, Process::WNOHANG).nil?
      rescue Errno::ECHILD
        true
      end
      private_class_method :reaped?

      def self.exited_within?(pid, timeout)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        until Process.wait(pid, Process::WNOHANG)
          return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

          sleep 0.05
        end
        true
      end
      private_class_method :exited_within?
    end
  end
end
