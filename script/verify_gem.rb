# frozen_string_literal: true

# Validates a built marcel gem against the exact manifest and identity a release is held to.
# Shared by test/package_test.rb and .github/workflows/release.yml so that what CI asserts on
# every push is the same check the release build runs.
#
#   ruby script/verify_gem.rb pkg/marcel-1.2.3.gem 1.2.3

require "rubygems/package"

module GemVerification
  ROOT = File.expand_path("..", __dir__)

  EXPECTED_FILES = %w(
    APACHE-LICENSE
    MIT-LICENSE
    README.md
    SECURITY.md
    lib/marcel.rb
    lib/marcel/magic.rb
    lib/marcel/magic/definitions.rb
    lib/marcel/magic/xml.rb
    lib/marcel/magic/zip.rb
    lib/marcel/mime_type.rb
    lib/marcel/mime_type/definitions.rb
    lib/marcel/tables.rb
    lib/marcel/version.rb
  ).freeze

  Error = Class.new(StandardError)

  class << self
    # Returns the verified specification, or raises GemVerification::Error.
    def verify!(path, expected_version)
      package = Gem::Package.new(path)
      package.verify
      spec = package.spec

      valid_identity = spec.name == "marcel" &&
        spec.version == Gem::Version.new(expected_version) &&
        spec.platform == Gem::Platform::RUBY &&
        File.basename(path) == spec.full_name + ".gem"
      raise Error, "unexpected gem identity: #{spec.full_name}" unless valid_identity
      raise Error, "unexpected runtime dependencies" unless spec.runtime_dependencies.empty?
      raise Error, "unexpected gem executables" unless spec.executables.empty?
      raise Error, "unexpected gem extensions" unless spec.extensions.empty?

      unless spec.files.sort == EXPECTED_FILES && package.contents.sort == EXPECTED_FILES
        raise Error, "unexpected gem manifest: #{(spec.files | package.contents).sort.inspect}"
      end

      EXPECTED_FILES.each do |entry|
        source = File.join(ROOT, entry)
        raise Error, "package source is missing or linked: #{entry}" unless File.file?(source) && !File.symlink?(source)
      end

      spec
    end
  end
end

if $PROGRAM_NAME == __FILE__
  abort "Usage: #{$0} path/to/marcel-VERSION.gem VERSION" unless ARGV.size == 2

  begin
    spec = GemVerification.verify!(*ARGV)
    puts "Verified #{spec.full_name}: #{GemVerification::EXPECTED_FILES.size} files, no runtime dependencies"
  rescue GemVerification::Error => error
    abort error.message
  end
end
