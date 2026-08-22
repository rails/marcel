require "test_helper"
require "open3"
require "rbconfig"
require "timeout"

class Marcel::MimeType::HtmlMagicTest < Marcel::TestCase
  test "does not override strong binary magic with a closing HTML tag" do
    fixtures = {
      "magic/image/jpeg/jpeg.jpg" => "image/jpeg",
      "magic/image/png/png.png" => "image/png",
      "magic/image/gif/gif.gif" => "image/gif",
      "magic/application/pdf/pdf.pdf" => "application/pdf",
      "magic/application/zip/zip.zip" => "application/zip",
    }

    fixtures.each do |fixture, content_type|
      polyglot = StringIO.new(File.binread(fixture_path(fixture)) + "\n</html>\n")

      assert_equal content_type, Marcel::MimeType.for(polyglot),
        "Expected #{fixture} magic to take precedence over a closing HTML tag"
    end
  end

  test "does not classify a comment-prefixed PDF ending in an HTML tag as HTML" do
    polyglot = StringIO.new(
      "<!-- leading comment -->\n" + File.binread(fixture_path("magic/application/pdf/pdf.pdf")) + "\n</html>\n"
    )

    refute_equal "text/html", Marcel::MimeType.for(polyglot)
  end

  test "recognizes an HTML document at the start of the data" do
    assert_equal "text/html", Marcel::MimeType.for(StringIO.new("<html><body>hello</body>"))
  end

  test "does not recognize an HTML tag at an arbitrary exact offset" do
    assert_equal "application/octet-stream", Marcel::MimeType.for(StringIO.new(("x" * 64) + "<html>"))
  end

  test "recognizes HTML after leading comments in a partial read" do
    html = "<!-- #{"x" * 512} -->\n<html><body>#{"x" * 5_000}</body></html>"
    chunk = html.byteslice(0, 4_096)

    assert_equal "text/html", Marcel::MimeType.for(
      StringIO.new(chunk), name: "page.html", declared_type: "text/html"
    )
  end

  test "recognizes HTML with a byte order mark" do
    html = "\xEF\xBB\xBF<html><body>hello</body>".b

    assert_equal "text/html", Marcel::MimeType.for(StringIO.new(html))
  end

  test "recognizes HTML after an XML declaration in a partial read" do
    html = "<?xml version=\"1.0\"?>\n<html><body>#{"x" * 5_000}</body></html>"
    chunk = html.byteslice(0, 4_096)

    assert_equal "text/html", Marcel::MimeType.for(
      StringIO.new(chunk), name: "page.html", declared_type: "text/html"
    )
  end

  test "keeps XHTML with its namespace as XHTML" do
    documents = [
      '<html xmlns="http://www.w3.org/1999/xhtml"><body></body></html>',
      '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><body></body></html>',
      '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"><html xmlns="http://www.w3.org/1999/xhtml"><body></body></html>',
      '<!DOCTYPE html><!-- comment --><html xmlns="http://www.w3.org/1999/xhtml"><body></body></html>',
      '<!DOCTYPE html><!-- one --><!-- two --><html xmlns="http://www.w3.org/1999/xhtml"><body></body></html>',
      '<?xml version="1.0"?><!-- before --><!DOCTYPE html><!-- after --><html xmlns="http://www.w3.org/1999/xhtml"><body></body></html>',
    ]

    documents.each do |document|
      assert_equal "application/xhtml+xml", Marcel::MimeType.for(StringIO.new(document))
    end
  end

  test "does not recognize XHTML from a loose namespace substring" do
    documents = [
      '<!DOCTYPE html><!-- comment --><html xmlns="urn:not-xhtml"></html>',
    ]
    documents.concat [1, 4_097, 8_192].map { |offset| ("x" * offset) + '<html xmlns="urn:not-xhtml"></html>' }

    documents.each_with_index do |document, index|
      types = Marcel::Magic.all_by_magic(StringIO.new(document)).map(&:type)

      refute_includes types, "application/xhtml+xml", "Unexpected XHTML match for document #{index}"
    end
  end

  test "matches XHTML names and namespace case-sensitively" do
    documents = [
      '<HTML xmlns="http://www.w3.org/1999/xhtml"></HTML>',
      '<html XMLNS="http://www.w3.org/1999/xhtml"></html>',
      '<html xmlns="http://www.w3.org/1999/XHTML"></html>',
    ]

    documents.each do |document|
      types = Marcel::Magic.all_by_magic(StringIO.new(document)).map(&:type)

      refute_includes types, "application/xhtml+xml"
    end
  end

  test "does not recognize XHTML from namespace text inside another attribute" do
    documents = [
      %q(<html title=' xmlns="http://www.w3.org/1999/xhtml" '></html>),
      %q(<html title=" xmlns='http://www.w3.org/1999/xhtml' "></html>),
    ]

    documents.each do |document|
      types = Marcel::Magic.all_by_magic(StringIO.new(document)).map(&:type)

      refute_includes types, "application/xhtml+xml"
    end
  end

  test "recognizes XHTML when its namespace follows other attributes" do
    document = '<html lang="en" xml:lang="en" xmlns="http://www.w3.org/1999/xhtml"></html>'

    assert_equal "application/xhtml+xml", Marcel::MimeType.for(StringIO.new(document))
  end

  test "does not classify valid MIDI text events as XHTML" do
    namespaces = ["urn:not-xhtml", "http://www.w3.org/1999/xhtml"]

    namespaces.each do |namespace|
      midi = midi_with_text_event(%(<html xmlns="#{namespace}"></html>))

      assert_equal "audio/midi", Marcel::MimeType.for(StringIO.new(midi))
      refute_includes Marcel::Magic.all_by_magic(StringIO.new(midi)).map(&:type), "application/xhtml+xml"
    end
  end

  test "preserves XHTML filename extensions" do
    %w[ page.xht page.xhtml page.xhtml2 ].each do |name|
      assert_equal "application/xhtml+xml", Marcel::MimeType.for(name: name)
    end
  end

  test "standalone Magic uses strict HTML and XHTML rules" do
    script = <<~'RUBY'
      require "stringio"
      require "marcel/magic"

      abort "MimeType unexpectedly loaded" if defined?(Marcel::MimeType)

      def types_for(content)
        Marcel::Magic.all_by_magic(StringIO.new(content)).map(&:type)
      end

      html = "<html><body></body></html>"
      xhtml = '<html xmlns="http://www.w3.org/1999/xhtml"></html>'
      quoted_namespace = %q(<html title=' xmlns="http://www.w3.org/1999/xhtml" '></html>)
      text = '<html xmlns="http://www.w3.org/1999/xhtml"></html>'.b
      track = "\x00\xFF\x01".b + [text.bytesize].pack("C") + text + "\x00\xFF\x2F\x00".b
      midi = "MThd".b + [6, 0, 1, 96].pack("Nnnn") + "MTrk".b + [track.bytesize].pack("N") + track

      abort "strict HTML magic missing" unless Marcel::Magic.by_magic(StringIO.new(html))&.type == "text/html"
      abort "strict XHTML magic missing" unless Marcel::Magic.by_magic(StringIO.new(xhtml))&.type == "application/xhtml+xml"
      abort "HTML extension missing" unless Marcel::Magic.by_extension("html")&.type == "text/html"
      abort "XHTML extension missing" unless Marcel::Magic.by_extension("xhtml")&.type == "application/xhtml+xml"
      abort "quoted namespace matched XHTML" if types_for(quoted_namespace).include?("application/xhtml+xml")

      midi_types = types_for(midi)
      abort "MIDI not detected" unless midi_types.include?("audio/midi")
      abort "MIDI matched HTML" if midi_types.include?("text/html")
      abort "MIDI matched XHTML" if midi_types.include?("application/xhtml+xml")
    RUBY

    _output, errors, status = Open3.capture3(
      RbConfig.ruby, "-I#{File.expand_path("../lib", __dir__)}", "-e", script
    )

    assert status.success?, errors
  end

  test "recognizes HTML containing SVG after a leading comment" do
    html = "<!-- leading comment -->\n<html><body><svg><script></script></svg>"

    assert_equal "text/html", Marcel::MimeType.for(StringIO.new(html))
  end

  test "recognizes HTML after many comments without pathological backtracking" do
    html = ("<!--x-->" * 400) + "<html><body></body></html>"

    content_type = Timeout.timeout(5) do
      Marcel::MimeType.for(StringIO.new(html))
    end

    assert_equal "text/html", content_type
  end

  test "keeps a comment-prefixed SVG as SVG" do
    svg = "<!-- leading comment -->\n<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>"

    assert_equal "image/svg+xml", Marcel::MimeType.for(StringIO.new(svg))
  end

  test "recognizes SVG after a short XML declaration" do
    svg = "<?xml version=\"1.0\"?>\n<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>"

    assert_equal "image/svg+xml", Marcel::MimeType.for(StringIO.new(svg))
  end

  test "does not promote generic XML to HTML from hints" do
    documents = [
      '<?xml version="1.0"?><root></root>',
      '<!-- leading comment --><root></root>',
    ]

    documents.each do |document|
      assert_equal "application/xml", Marcel::MimeType.for(
        StringIO.new(document), name: "page.html", declared_type: "text/html"
      )
    end
  end

  test "does not treat a partial prefix as the end of a long HTML document" do
    # Past the HTML magic window, the root element scan still finds <html> within its own
    # 64KB bound; a prefix cut before the root element, or a root beyond that bound, is not HTML.
    html = "<!-- #{"x" * 5_000} -->\n<html><body></body></html>"
    chunk = html.byteslice(0, 4_096)
    distant = "<!-- #{"x" * 70_000} -->\n<html><body></body></html>"

    assert_equal "text/html", Marcel::MimeType.for(StringIO.new(html))
    assert_equal "application/xml", Marcel::MimeType.for(StringIO.new(chunk))
    assert_equal "application/xml", Marcel::MimeType.for(StringIO.new(distant))
  end

  private

    def midi_with_text_event(text)
      text = text.b
      track = "\x00\xFF\x01".b + [text.bytesize].pack("C") + text + "\x00\xFF\x2F\x00".b
      "MThd".b + [6, 0, 1, 96].pack("Nnnn") + "MTrk".b + [track.bytesize].pack("N") + track
    end
end
