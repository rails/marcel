require "test_helper"
require "open3"
require "rbconfig"
require "tmpdir"

class Marcel::GenerateTablesTest < Marcel::TestCase
  test "serializes XML data as inert Ruby source" do
    xml = <<-'XML'
      <mime-info>
        <mime-type type="application/x-bzip2">
          <magic>
            <match type="regex" value="#{raise(&quot;regex interpolation executed&quot;)}" />
          </magic>
        </mime-type>
        <mime-type type="application/x-generated">
          <_comment>Generated comment&#10;raise "comment injection executed"</_comment>
          <glob pattern="*.safe" />
          <sub-class-of type="application/zip" />
        </mime-type>
      </mime-info>
    XML

    Dir.mktmpdir("marcel-generator-test") do |directory|
      xml_path = File.join(directory, "input.xml")
      tables_path = File.join(directory, "tables.rb")
      File.binwrite(xml_path, xml)

      generated, errors, status = Open3.capture3(
        RbConfig.ruby, File.expand_path("../script/generate_tables.rb", __dir__), xml_path
      )
      assert status.success?, errors
      assert_includes generated, "Regexp.new("
      File.binwrite(tables_path, generated)

      verification = "load ARGV.fetch(0); abort unless Marcel::EXTENSIONS.key?(ARGV.fetch(1))"
      _output, errors, status = Open3.capture3(
        RbConfig.ruby, "-e", verification, tables_path, "safe"
      )
      assert status.success?, errors
    end
  end

  test "rejects code-shaped MIME fields" do
    xml = <<-'XML'
      <mime-info>
        <mime-type type="application/x-pwn&apos;]; raise(&quot;type interpolation executed&quot;); #">
          <glob pattern="*.safe" />
        </mime-type>
      </mime-info>
    XML

    Dir.mktmpdir("marcel-generator-test") do |directory|
      xml_path = File.join(directory, "input.xml")
      File.binwrite(xml_path, xml)

      generated, errors, status = Open3.capture3(
        RbConfig.ruby, File.expand_path("../script/generate_tables.rb", __dir__), xml_path
      )

      refute status.success?
      assert_empty generated
      assert_includes errors, "Invalid MIME type"
    end
  end

  test "rejects malformed XML instead of recovering it" do
    xml = '<mime-info><mime-type type="text/plain"><glob pattern="*.txt" /></mime-info>'

    Dir.mktmpdir("marcel-generator-test") do |directory|
      xml_path = File.join(directory, "input.xml")
      File.binwrite(xml_path, xml)

      generated, errors, status = Open3.capture3(
        RbConfig.ruby, File.expand_path("../script/generate_tables.rb", __dir__), xml_path
      )

      refute status.success?
      assert_empty generated
      assert_includes errors, "Nokogiri::XML::SyntaxError"
    end
  end

  test "normalizes surrounding MIME type whitespace" do
    xml = <<-'XML'
      <mime-info>
        <mime-type type="application/vnd.java.hprof ">
          <glob pattern="*.hprof" />
        </mime-type>
        <mime-type type="application/x-example; version=1">
          <glob pattern="*.example" />
        </mime-type>
      </mime-info>
    XML

    Dir.mktmpdir("marcel-generator-test") do |directory|
      xml_path = File.join(directory, "input.xml")
      tables_path = File.join(directory, "tables.rb")
      File.binwrite(xml_path, xml)

      generated, errors, status = Open3.capture3(
        RbConfig.ruby, File.expand_path("../script/generate_tables.rb", __dir__), xml_path
      )
      assert status.success?, errors
      File.binwrite(tables_path, generated)

      verification = <<~'RUBY'
        load ARGV.fetch(0)
        abort unless Marcel::EXTENSIONS.fetch("hprof") == "application/vnd.java.hprof"
        abort if Marcel::TYPE_EXTS.key?("application/vnd.java.hprof ")
        abort unless Marcel::EXTENSIONS.fetch("example") == "application/x-example; version=1"
      RUBY
      _output, errors, status = Open3.capture3(RbConfig.ruby, "-e", verification, tables_path)
      assert status.success?, errors
    end
  end

  test "rejects control characters before normalizing MIME fields" do
    xml = <<-'XML'
      <mime-info>
        <mime-type type="&#xA;application/x-hidden">
          <glob pattern="*.hidden" />
        </mime-type>
      </mime-info>
    XML

    Dir.mktmpdir("marcel-generator-test") do |directory|
      xml_path = File.join(directory, "input.xml")
      File.binwrite(xml_path, xml)

      generated, errors, status = Open3.capture3(
        RbConfig.ruby, File.expand_path("../script/generate_tables.rb", __dir__), xml_path
      )

      refute status.success?
      assert_empty generated
      assert_includes errors, "Invalid MIME type"
    end
  end

  test "bounds offsets, ranges, and priorities before converting them" do
    invalid_values = [
      [ "offset", "65537", "Magic offset exceeds 65536" ],
      [ "offset", "0:65536", "Magic range exceeds 65536 bytes" ],
      [ "offset", "2:1", "Descending magic offset" ],
      [ "offset", "1#{'0' * 100}", "Invalid magic offset" ],
      [ "priority", "101", "Magic priority exceeds 100" ],
      [ "priority", "1#{'0' * 100}", "Invalid magic priority" ],
    ]

    Dir.mktmpdir("marcel-generator-test") do |directory|
      invalid_values.each_with_index do |(attribute, value, message), index|
        magic_attribute = attribute == "priority" ? %( priority="#{value}") : ""
        match_attribute = attribute == "offset" ? %( offset="#{value}") : ""
        xml = <<~XML
          <mime-info>
            <mime-type type="application/x-bounded">
              <magic#{magic_attribute}>
                <match type="string" value="BOUND"#{match_attribute} />
              </magic>
            </mime-type>
          </mime-info>
        XML
        xml_path = File.join(directory, "invalid-#{index}.xml")
        File.binwrite(xml_path, xml)

        generated, errors, status = Open3.capture3(
          RbConfig.ruby, File.expand_path("../script/generate_tables.rb", __dir__), xml_path
        )

        refute status.success?, "accepted #{attribute}=#{value.inspect}"
        assert_empty generated
        assert_includes errors, message
      end
    end
  end

  test "accepts the bounded offset range and priority limits" do
    xml = <<-'XML'
      <mime-info>
        <mime-type type="application/x-bounded">
          <magic priority="100">
            <match type="string" value="FIXED" offset="65536" />
            <match type="string" value="RANGE" offset="1:65536" />
          </magic>
        </mime-type>
      </mime-info>
    XML

    Dir.mktmpdir("marcel-generator-test") do |directory|
      xml_path = File.join(directory, "input.xml")
      File.binwrite(xml_path, xml)

      generated, errors, status = Open3.capture3(
        RbConfig.ruby, File.expand_path("../script/generate_tables.rb", __dir__), xml_path
      )

      assert status.success?, errors
      assert_includes generated, "65536"
      assert_includes generated, "1..65536"
    end
  end

  test "uses source order to break equal magic priority ties" do
    xml = <<-'XML'
      <mime-info>
        <mime-type type="application/x-ordered">
          <magic priority="50"><match type="string" value="FIRST" /></magic>
          <magic priority="50"><match type="string" value="SECOND" /></magic>
        </mime-type>
      </mime-info>
    XML

    Dir.mktmpdir("marcel-generator-test") do |directory|
      xml_path = File.join(directory, "input.xml")
      File.binwrite(xml_path, xml)

      generated, errors, status = Open3.capture3(
        RbConfig.ruby, File.expand_path("../script/generate_tables.rb", __dir__), xml_path
      )

      assert status.success?, errors
      assert_operator generated.index("FIRST"), :<, generated.index("SECOND")
    end
  end

  test "pins the reviewed unsupported Tika rule set" do
    Dir.mktmpdir("marcel-generator-test") do |directory|
      tables_path = File.join(directory, "tables.rb")
      _generated, errors, status = Open3.capture3(
        RbConfig.ruby,
        File.expand_path("../script/generate_tables.rb", __dir__),
        "--output", tables_path,
        File.expand_path("../data/tika.xml", __dir__),
        File.expand_path("../data/custom.xml", __dir__)
      )

      assert status.success?, errors
      warning_lines = errors.lines
      assert_equal "Skipped 58 unsupported magic rules\n", warning_lines.pop
      assert_equal 112, warning_lines.size
      assert File.exist?(tables_path)
    end
  end

  test "verifies the committed Tika source against its pinned checksum" do
    _output, errors, status = Open3.capture3(
      RbConfig.ruby,
      File.expand_path("../script/download_tika_data.rb", __dir__),
      "--verify", File.expand_path("../data/tika.xml", __dir__)
    )

    assert status.success?, errors
  end

  test "rejects altered committed Tika source data" do
    tika_data = File.binread(File.expand_path("../data/tika.xml", __dir__))
    alterations = [
      tika_data.sub("<!-- Downloaded from ", "<!-- Copied from "),
      tika_data.sub('pattern="*.ez"', 'pattern="*.unexpected-ez"'),
    ]

    Dir.mktmpdir("marcel-generator-test") do |directory|
      alterations.each_with_index do |altered_data, index|
        refute_equal tika_data, altered_data
        xml_path = File.join(directory, "altered-#{index}.xml")
        File.binwrite(xml_path, altered_data)

        output, errors, status = Open3.capture3(
          RbConfig.ruby,
          File.expand_path("../script/download_tika_data.rb", __dir__),
          "--verify", xml_path
        )

        refute status.success?
        assert_empty output
        assert_includes errors, "Unexpected Tika"
      end
    end
  end

  test "rejects an unreviewed unsupported rule without emitting output" do
    xml = <<-'XML'
      <mime-info>
        <mime-type type="application/x-unsupported">
          <magic>
            <match type="regex" value="UNREVIEWED" />
          </magic>
        </mime-type>
      </mime-info>
    XML

    Dir.mktmpdir("marcel-generator-test") do |directory|
      xml_path = File.join(directory, "input.xml")
      File.binwrite(xml_path, xml)

      generated, errors, status = Open3.capture3(
        RbConfig.ruby, File.expand_path("../script/generate_tables.rb", __dir__), xml_path
      )

      refute status.success?
      assert_empty generated
      assert_includes errors, "Unsupported magic rules changed"
      assert_includes errors, "got 1"
    end
  end

  test "buffers stdout until every rule has serialized" do
    xml = <<-'XML'
      <mime-info>
        <mime-type type="application/x-bzip2">
          <magic>
            <match type="regex" value="[" />
          </magic>
        </mime-type>
      </mime-info>
    XML

    Dir.mktmpdir("marcel-generator-test") do |directory|
      xml_path = File.join(directory, "input.xml")
      File.binwrite(xml_path, xml)

      generated, errors, status = Open3.capture3(
        RbConfig.ruby, File.expand_path("../script/generate_tables.rb", __dir__), xml_path
      )

      refute status.success?
      assert_empty generated
      assert_match(/premature end of char-class|unterminated character class/, errors)
    end
  end

  test "preserves an existing output file when direct generation fails" do
    malformed_xml = '<mime-info><mime-type type="text/plain"></mime-info>'

    Dir.mktmpdir("marcel-generator-test") do |directory|
      xml_path = File.join(directory, "input.xml")
      tables_path = File.join(directory, "tables.rb")
      File.binwrite(xml_path, malformed_xml)
      File.binwrite(tables_path, "existing artifact\n")

      generated, _errors, status = Open3.capture3(
        RbConfig.ruby, File.expand_path("../script/generate_tables.rb", __dir__),
        "--output", tables_path, xml_path
      )

      refute status.success?
      assert_empty generated
      assert_equal "existing artifact\n", File.binread(tables_path)
    end
  end

  test "keeps extensions but omits broad generated HTML magic" do
    xml = <<-'XML'
      <mime-info>
        <mime-type type="text/html">
          <glob pattern="*.html" />
          <magic><match type="string" value="&lt;html" offset="0:8192" /></magic>
        </mime-type>
        <mime-type type="application/xhtml+xml">
          <glob pattern="*.xhtml" />
          <magic><match type="string" value="&lt;html xmlns=" offset="0:8192" /></magic>
        </mime-type>
      </mime-info>
    XML

    Dir.mktmpdir("marcel-generator-test") do |directory|
      xml_path = File.join(directory, "input.xml")
      tables_path = File.join(directory, "tables.rb")
      File.binwrite(xml_path, xml)

      generated, errors, status = Open3.capture3(
        RbConfig.ruby, File.expand_path("../script/generate_tables.rb", __dir__), xml_path
      )
      assert status.success?, errors
      File.binwrite(tables_path, generated)

      verification = <<~'RUBY'
        load ARGV.fetch(0)
        abort unless Marcel::EXTENSIONS.fetch("html") == "text/html"
        abort unless Marcel::EXTENSIONS.fetch("xhtml") == "application/xhtml+xml"
        abort unless Marcel::MAGIC.none? { |type, _| type == "text/html" || type == "application/xhtml+xml" }
      RUBY
      _output, errors, status = Open3.capture3(RbConfig.ruby, "-e", verification, tables_path)
      assert status.success?, errors
    end
  end

  test "probes common types first, behind higher-priority matchers for their own subtypes" do
    xml = <<-'XML'
      <mime-info>
        <mime-type type="image/x-other">
          <magic priority="50"><match type="string" value="OTHER" offset="0" /></magic>
        </mime-type>
        <mime-type type="application/x-unrelated">
          <magic priority="60"><match type="string" value="UNREL" offset="0" /></magic>
        </mime-type>
        <mime-type type="image/x-tiff-flavour">
          <sub-class-of type="image/x-tiff-family" />
          <magic priority="60"><match type="string" value="II*\000CR" offset="0" /></magic>
        </mime-type>
        <mime-type type="image/x-tiff-family">
          <sub-class-of type="image/tiff" />
        </mime-type>
        <mime-type type="image/tiff">
          <magic priority="50"><match type="string" value="II*\000" offset="0" /></magic>
        </mime-type>
        <mime-type type="image/jpeg">
          <magic priority="50"><match type="string" value="\377\330\377" offset="0" /></magic>
        </mime-type>
      </mime-info>
    XML

    Dir.mktmpdir("marcel-generator-test") do |directory|
      xml_path = File.join(directory, "input.xml")
      tables_path = File.join(directory, "tables.rb")
      File.binwrite(xml_path, xml)

      generated, errors, status = Open3.capture3(
        RbConfig.ruby, File.expand_path("../script/generate_tables.rb", __dir__), xml_path
      )
      assert status.success?, errors
      File.binwrite(tables_path, generated)

      verification = <<~'RUBY'
        load ARGV.fetch(0)
        expected = %w( image/jpeg image/x-tiff-flavour image/tiff application/x-unrelated image/x-other )
        abort Marcel::MAGIC.map(&:first).inspect unless Marcel::MAGIC.map(&:first) == expected
      RUBY
      _output, errors, status = Open3.capture3(RbConfig.ruby, "-e", verification, tables_path)
      assert status.success?, errors
    end
  end
end
