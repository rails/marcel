require "test_helper"
require "rubygems/package"
require "stringio"
require "tempfile"
require "tmpdir"
require "zlib"

class Marcel::PackageTest < Marcel::TestCase
  PROJECT_ROOT = File.expand_path("..", __dir__)
  PACKAGE_FILES = %w(
    APACHE-LICENSE
    MIT-LICENSE
    README.md
    SECURITY.md
    lib/marcel.rb
    lib/marcel/magic.rb
    lib/marcel/magic/definitions.rb
    lib/marcel/mime_type.rb
    lib/marcel/mime_type/definitions.rb
    lib/marcel/tables.rb
    lib/marcel/version.rb
  ).freeze

  test "packages the exact regular-file manifest" do
    PACKAGE_FILES.each do |path|
      stat = File.lstat(File.join(PROJECT_ROOT, path))
      assert stat.file?, "expected #{path} to be a regular file"
    end

    Tempfile.create([ "marcel", ".gem" ]) do |temporary|
      gem_path = temporary.path
      temporary.close

      Dir.chdir(PROJECT_ROOT) do
        capture_io { Gem::Package.build(specification, false, false, gem_path) }
      end

      package = Gem::Package.new(gem_path)
      assert_equal PACKAGE_FILES, package.contents.sort
      assert_equal PACKAGE_FILES, package.spec.files.sort

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

  test "locks runtime dependencies with the Bundler supported by Ruby 2.7" do
    lock = File.binread(File.join(PROJECT_ROOT, "gemfiles/runtime/Gemfile.lock"))
    assert_equal "https://rubygems.org/", lock[/^GEM\n  remote: (.+)$/, 1]
    refute_match(/^CHECKSUMS$/, lock)
    assert_match(/\nBUNDLED WITH\n   2\.4\.22\n?\z/, lock)
  end

  test "requires the oldest Ruby exercised by CI" do
    assert specification.required_ruby_version.satisfied_by?(Gem::Version.new("2.7.0"))
    refute specification.required_ruby_version.satisfied_by?(Gem::Version.new("2.6.10"))
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
