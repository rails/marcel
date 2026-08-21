require "test_helper"
require "open3"
require "rbconfig"
require "rubygems/package"
require "stringio"
require "tempfile"
require "tmpdir"
require "zlib"
require_relative "../script/verify_gem"

class Marcel::PackageTest < Marcel::TestCase
  PROJECT_ROOT = File.expand_path("..", __dir__)
  VERIFY_GEM = File.join(PROJECT_ROOT, "script/verify_gem.rb")

  # The manifest lives in the release validator so CI and the release build hold the gem to
  # the same file list.
  PACKAGE_FILES = GemVerification::EXPECTED_FILES

  test "packages the exact regular-file manifest" do
    PACKAGE_FILES.each do |path|
      stat = File.lstat(File.join(PROJECT_ROOT, path))
      assert stat.file?, "expected #{path} to be a regular file"
    end

    Dir.mktmpdir("marcel-package-test") do |directory|
      gem_path = File.join(directory, "marcel-#{Marcel::VERSION}.gem")

      Dir.chdir(PROJECT_ROOT) do
        capture_io { Gem::Package.build(specification, false, false, gem_path) }
      end

      package = Gem::Package.new(gem_path)
      assert_equal PACKAGE_FILES, package.contents.sort
      assert_equal PACKAGE_FILES, package.spec.files.sort
      assert_equal "marcel", GemVerification.verify!(gem_path, Marcel::VERSION).name

      output, errors, status = Open3.capture3(RbConfig.ruby, VERIFY_GEM, gem_path, Marcel::VERSION)
      assert status.success?, errors
      assert_includes output, "Verified marcel-#{Marcel::VERSION}"

      _output, errors, status = Open3.capture3(RbConfig.ruby, VERIFY_GEM, gem_path, "0.0.0")
      refute status.success?
      assert_includes errors, "unexpected gem identity"

      data_archive = nil
      File.open(gem_path, "rb") do |gem|
        Gem::Package::TarReader.new(gem) do |entries|
          entries.each do |entry|
            if entry.full_name == "data.tar.gz"
              data_archive = entry.read
              break
            end
          end
        end
      end
      refute_nil data_archive
      packaged_entries = Zlib::GzipReader.wrap(StringIO.new(data_archive)) do |data|
        Gem::Package::TarReader.new(data).map { |entry| [ entry.full_name, entry.file? ] }
      end

      assert_equal PACKAGE_FILES, packaged_entries.map(&:first).sort
      assert packaged_entries.all?(&:last), "expected every packaged entry to be a regular file"
    end
  end

  test "packages both licenses and no runtime dependencies" do
    assert_equal %w(Apache-2.0 MIT), specification.licenses.sort
    assert_empty specification.runtime_dependencies
  end

  test "locks runtime dependencies with checksums using the same Bundler as the main lock" do
    lock = File.binread(File.join(PROJECT_ROOT, "gemfiles/runtime/Gemfile.lock"))
    main_lock = File.binread(File.join(PROJECT_ROOT, "Gemfile.lock"))

    assert_equal "https://rubygems.org/", lock[/^GEM\n  remote: (.+)$/, 1]
    assert_match(/^CHECKSUMS$/, lock)
    assert_equal main_lock[/\nBUNDLED WITH\n\s+(\S+)/, 1], lock[/\nBUNDLED WITH\n\s+(\S+)/, 1]
  end

  test "requires the oldest Ruby exercised by CI" do
    assert specification.required_ruby_version.satisfied_by?(Gem::Version.new("3.3.0"))
    refute specification.required_ruby_version.satisfied_by?(Gem::Version.new("3.2.9"))
  end

  test "loads package metadata outside the project directory" do
    Dir.mktmpdir do |directory|
      Dir.chdir(directory) do
        assert_empty PACKAGE_FILES - specification.files
      end
    end
  end

  private
    def specification
      Dir.chdir(PROJECT_ROOT) do
        Gem::Specification.load(File.join(PROJECT_ROOT, "marcel.gemspec"))
      end
    end
end
