# frozen_string_literal: true

require_relative 'codegraph/version'
require_relative 'codegraph/config'
require_relative 'codegraph/lock'
require_relative 'codegraph/indexer'
require_relative 'codegraph/backfill'

module Bundler

  # Bundler plugin building a CodeGraph index inside every gem it installs, so
  # that an agent can query a dependency's source through `codegraph explore
  # --path <gem>` instead of reading its files by hand.
  module Codegraph

    # Entry point wired to Bundler's `after-install` hook.
    #
    # Swallows everything: the hook also fires for failed installs, and a broken
    # index must never be the reason a `bundle install` aborts.
    #
    # @param spec_install [Bundler::ParallelInstaller::SpecInstallation]
    # @return [Symbol, nil] the indexing status, nil when the gem was not installed
    def self.after_install(spec_install)
      return unless spec_install.respond_to?(:installed?) && spec_install.installed?

      spec = spec_install.spec
      Indexer.new(spec.full_gem_path, name: spec.name).call
    rescue StandardError
      nil
    end
  end
end
