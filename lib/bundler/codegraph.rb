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
    # @param root [Pathname, String] root of the project being installed
    # @param config [Config]
    # @return [Symbol, nil] the indexing status, nil when the gem was skipped
    def self.after_install(spec_install, root: Bundler.root, config: Config.new)
      return unless spec_install.respond_to?(:installed?) && spec_install.installed?

      spec = spec_install.spec
      return unless dependency?(spec, root)

      Indexer.new(spec.full_gem_path, name: spec.name, config: config).call
    rescue StandardError
      nil
    end

    # Whether a spec of the bundle is a dependency worth indexing. `bundler`
    # itself lives in the Ruby installation, outside the bundle. A project
    # declaring `gemspec` gets its own spec back as a `path:` source rooted at
    # the project directory, which is the project, not a dependency: it is
    # told by its `Bundler::Source::Gemspec` source, since the Gemfile need not
    # sit at the root (Appraisal's `gemfiles/*.gemfile` use `gemspec path:
    # '../'`), and by its path for specs that carry no source.
    #
    # @param spec [#name, #full_gem_path]
    # @param root [Pathname, String] root of the project
    def self.dependency?(spec, root)
      return false if spec.name == 'bundler' || own_gemspec?(spec)

      File.expand_path(spec.full_gem_path) != File.expand_path(root.to_s)
    end

    def self.own_gemspec?(spec)
      defined?(Bundler::Source::Gemspec) && spec.respond_to?(:source) && spec.source.is_a?(Bundler::Source::Gemspec)
    end
    private_class_method :own_gemspec?
  end
end
