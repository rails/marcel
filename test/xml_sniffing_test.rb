require 'test_helper'

class Marcel::MimeType::XmlSniffingTest < Marcel::TestCase
  # An IO that supports sequential reads and rewind but neither seek nor size, like a
  # non-rewindable pipe wrapper buffered by Rack.
  class UnseekableIO
    def initialize(data)
      @io = StringIO.new(data)
    end

    def read(length = nil, buffer = nil)
      @io.read(length, buffer)
    end

    def rewind
      @io.rewind
    end
  end

  # A StringIO that counts the bytes handed out by read.
  class CountingIO < StringIO
    attr_reader :bytes_read

    def read(*)
      super.tap { |chunk| @bytes_read = (@bytes_read || 0) + chunk.to_s.bytesize }
    end
  end

  DECLARATION = '<?xml version="1.0" encoding="UTF-8"?>'

  def detect(data, **hints)
    Marcel::MimeType.for(StringIO.new(data), **hints)
  end

  def xml(body)
    "#{DECLARATION}\n#{body}"
  end

  test "RSS feeds are detected from content" do
    assert_equal "application/rss+xml", detect(xml('<rss version="2.0"><channel><title>t</title></channel></rss>'))
  end

  test "Atom feeds are detected from content under both namespaces" do
    assert_equal "application/atom+xml", detect(xml('<feed xmlns="http://www.w3.org/2005/Atom"><title>t</title></feed>'))
    assert_equal "application/atom+xml", detect(xml('<feed xmlns="http://purl.org/atom/ns#" version="0.3"><title>t</title></feed>'))
  end

  test "KML is detected bare, under every namespace, and with a prefixed root" do
    assert_equal "application/vnd.google-earth.kml+xml", detect(xml('<kml><Placemark/></kml>'))

    %w( http://www.opengis.net/kml/2.2 http://earth.google.com/kml/2.0
        http://earth.google.com/kml/2.1 http://earth.google.com/kml/2.2 ).each do |namespace|
      assert_equal "application/vnd.google-earth.kml+xml", detect(xml(%(<kml xmlns="#{namespace}"><Placemark/></kml>)))
    end

    assert_equal "application/vnd.google-earth.kml+xml",
      detect(xml('<k:kml xmlns:k="http://www.opengis.net/kml/2.2"><k:Placemark/></k:kml>'))
  end

  test "XHTML with a prefixed root is detected by namespace" do
    assert_equal "application/xhtml+xml", detect(xml('<h:html xmlns:h="http://www.w3.org/1999/xhtml"><h:body/></h:html>'))
  end

  test "property lists are detected past their DOCTYPE" do
    plist = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict><key>Name</key><string>Marcel</string></dict>
      </plist>
    XML
    assert_equal "application/x-plist", detect(plist)
  end

  test "XSLT stylesheets are detected by namespace" do
    assert_equal "application/xslt+xml",
      detect(xml('<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"/>'))
  end

  test "ONIX collisions resolve to the first type by name, as Tika does" do
    assert_equal "application/onix-message+xml",
      detect(xml('<ONIXMessage xmlns="http://ns.editeur.org/onix/3.0/reference" release="3.0"/>'))
    assert_equal "application/onix-message+xml", detect(xml('<ONIXMessage release="3.0"/>'))
  end

  test "iWork flat XML documents are detected by namespace" do
    assert_equal "application/vnd.apple.pages", detect(xml('<sl:document xmlns:sl="http://developer.apple.com/namespaces/sl"/>'))
    assert_equal "application/vnd.apple.numbers", detect(xml('<ls:document xmlns:ls="http://developer.apple.com/namespaces/ls"/>'))
    assert_equal "application/vnd.apple.keynote", detect(xml('<key:presentation xmlns:key="http://developer.apple.com/namespaces/keynote2"/>'))
  end

  test "Office 2003 XML documents are detected past their application processing instruction" do
    word = xml(<<~XML)
      <?mso-application progid="Word.Document"?>
      <w:wordDocument xmlns:w="http://schemas.microsoft.com/office/word/2003/wordml"><w:body/></w:wordDocument>
    XML
    excel = xml(<<~XML)
      <?mso-application progid="Excel.Sheet"?>
      <Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"><Worksheet/></Workbook>
    XML

    assert_equal "application/vnd.ms-wordml", detect(word)
    assert_equal "application/vnd.ms-spreadsheetml", detect(excel)
  end

  test "aliased table values are canonicalized" do
    assert_equal "application/x-xliff+xml", Marcel::ROOT_XML[["urn:oasis:names:tc:xliff:document:1.2", "xliff"]]
    assert_equal "application/xliff+xml", detect(xml('<xliff xmlns="urn:oasis:names:tc:xliff:document:1.2" version="1.2"/>'))
  end

  test "un-namespaced HTML fragment roots are HTML, as Tika labels them" do
    %w( body p script frameset iframe link BODY P SCRIPT ).each do |root|
      assert_equal "text/html", detect(xml("<#{root}>x</#{root}>")), root
    end
  end

  test "unknown and namespaced-but-unlisted roots keep the generic type" do
    assert_equal "application/xml", detect(xml('<manifest xmlns="urn:example:manifest"/>'))
    assert_equal "application/xml", detect(xml('<rss xmlns="urn:example:not-rss" version="2.0"/>'))
    assert_equal "application/xml", detect(xml('<body xmlns="urn:example:not-html"/>'))
  end

  test "documents without a declaration or leading comment never reach the sniffer" do
    assert_equal "application/octet-stream", detect('<rss version="2.0"><channel/></rss>')
  end

  test "a leading comment still reaches the root element" do
    assert_equal "application/rss+xml", detect("<!-- generated by a feed builder -->\n<rss version=\"2.0\"><channel/></rss>")
    assert_equal "application/atom+xml", detect(xml("<!-- one -->\n<!-- two\n spans lines -->\n<feed xmlns=\"http://www.w3.org/2005/Atom\"/>"))
  end

  test "internal DTD subsets containing quoted markup and comments do not end the prolog early" do
    document = xml(<<~XML)
      <!DOCTYPE rss [
        <!ENTITY brand "<b>Acme</b>">
        <!ENTITY quote '"quoted"'>
        <!-- don't stop here > -->
        <?pi with > inside?>
        <!ELEMENT rss (channel)>
      ]>
      <rss version="2.0"><channel><title>&brand;</title></channel></rss>
    XML

    assert_equal "application/rss+xml", detect(document)
  end

  test "attribute values containing angle brackets do not truncate the start-tag" do
    assert_equal "application/rss+xml", detect(xml('<rss version="2.0" note="a > b"><channel/></rss>'))
    assert_equal "application/vnd.google-earth.kml+xml", detect(xml(%(<kml note='x > y' xmlns="http://www.opengis.net/kml/2.2"/>)))
  end

  test "start-tags spanning lines and non-ASCII attribute names are read" do
    assert_equal "application/atom+xml", detect(xml(%(<feed\n    xml:lang="en"\n\ttítulo="x"\n    xmlns="http://www.w3.org/2005/Atom"\n>\n</feed>)))
  end

  test "an empty xmlns declaration puts the root in no namespace" do
    assert_equal "application/rss+xml", detect(xml('<rss xmlns="" version="2.0"/>'))
  end

  test "byte order marks are honoured" do
    utf8 = "\xEF\xBB\xBF".b + xml('<rss version="2.0"/>').b
    utf16le = "﻿#{xml('<rss version="2.0"/>')}".encode(Encoding::UTF_16LE).b
    utf16be = "﻿#{xml('<feed xmlns="http://www.w3.org/2005/Atom"/>')}".encode(Encoding::UTF_16BE).b

    assert_equal "application/rss+xml", detect(utf8)
    assert_equal "application/rss+xml", detect(utf16le)
    assert_equal "application/atom+xml", detect(utf16be)
  end

  test "odd-length UTF-16 truncation is harmless after the root and fail-closed within it" do
    document = "﻿#{xml('<rss version="2.0"><channel><title>feed</title></channel></rss>')}".encode(Encoding::UTF_16LE).b
    root_end = document.index(">\0".b, document.index("<\0r\0s\0s\0".b)) + 2

    assert_equal "application/rss+xml", detect(document[0, root_end + 7])
    assert_equal "application/xml", detect(document[0, root_end - 3])
  end

  test "a start-tag truncated by the scan limit keeps the generic type" do
    prolog = DECLARATION + "<!--" + ("x" * (Marcel::Magic::Xml::MAX_SCAN - DECLARATION.bytesize - 20)) + "-->"
    document = prolog + '<rss version="2.0"><channel/></rss>'

    assert_operator document.index('<rss'), :<, Marcel::Magic::Xml::MAX_SCAN
    assert_operator document.index('<rss') + '<rss version="2.0">'.bytesize, :>, Marcel::Magic::Xml::MAX_SCAN
    assert_equal "application/xml", detect(document)
  end

  test "a root element beyond the scan limit keeps the generic type" do
    document = DECLARATION + "<!--" + ("x" * Marcel::Magic::Xml::MAX_SCAN) + "--><rss version=\"2.0\"/>"

    assert_equal "application/xml", detect(document)
  end

  test "malformed prologs keep the generic type" do
    assert_equal "application/xml", detect(DECLARATION)
    assert_equal "application/xml", detect(xml('garbage <rss version="2.0"/>'))
    assert_equal "application/xml", detect(xml('<!-- unterminated <rss version="2.0"/>'))
    assert_equal "application/xml", detect(xml('<!DOCTYPE rss [ <!ENTITY x "unterminated> ]><rss/>'))
    assert_equal "application/xml", detect(xml('<rss version="2.0" <channel/></rss>'))
    assert_equal "application/xml", detect(xml('<k:kml><k:Placemark/></k:kml>'))
  end

  test "deliberately unsupported XML semantics keep the generic type rather than guessing" do
    # A SAX parser would resolve the character reference, apply the #FIXED default, and
    # normalize the newline. Marcel reads attribute values literally; no table key contains
    # whitespace, so normalization could never change a verdict anyway.
    assert_equal "application/xml", detect(xml('<feed xmlns="http://www.w3.org/2005/&#65;tom"/>'))
    assert_equal "application/xml", detect(xml('<!DOCTYPE feed [<!ATTLIST feed xmlns CDATA #FIXED "http://www.w3.org/2005/Atom">]><feed/>'))
    assert_equal "application/xml", detect(xml(%(<feed xmlns="http://www.w3.org/2005/\nAtom"/>)))
  end

  test "bytes invalid in the document encoding keep the generic type wherever they fall before the root" do
    # Tika's SAX parser fails before the first start element, so nothing is refined — even
    # when the bad bytes sit in a comment or attribute the lookup key never touches.
    assert_equal "application/xml", detect(xml("<!-- \xFF --><rss version=\"2.0\"/>".b))
    assert_equal "application/xml", detect(xml("<!-- \xFF --><body/>".b))
    assert_equal "application/xml", detect(xml(%(<rss version="2.0" note="\xFF"/>).b))
    assert_equal "application/xml", detect(%(<?xml version="1.0" encoding="Shift_JIS"?><!-- \x82 --><rss/>).b)

    lone_surrogate = "﻿#{xml('<!-- X --><rss/>')}".encode(Encoding::UTF_16LE).b
    lone_surrogate[lone_surrogate.index("X\0".b), 2] = "\x00\xD8".b
    assert_equal "application/xml", detect(lone_surrogate)
  end

  test "declared encodings are validated as declared, not assumed to be UTF-8" do
    assert_equal "application/rss+xml", detect(%(<?xml version="1.0" encoding="ISO-8859-1"?><!-- caf\xE9 --><rss/>).b)
    assert_equal "application/rss+xml", detect(%(<?xml version="1.0" encoding="Shift_JIS"?><!-- \x82\xA0 --><rss/>).b)
    assert_equal "application/rss+xml", detect(%(<?xml version="1.0" encoding="utf-8"?><!-- café --><rss/>))
    assert_equal "application/xml", detect(%(<?xml version="1.0" encoding="x-unknown"?><rss/>))
    assert_equal "application/xml", detect(%(<?xml version="1.0" encoding="locale"?><rss/>))
    assert_equal "application/xml", detect(%(<?xml version="1.0" encoding="UTF-16"?><rss/>))
  end

  test "legacy multibyte encodings whose trail bytes look like ASCII are read as characters" do
    # Shift_JIS ソ is 83 5C — its trail byte is an ASCII backslash — and ‐ is 81 5D,
    # trailing in an ASCII ], so a raw byte scan would derail inside a name, a value,
    # or a DOCTYPE internal subset.
    sjis = ->(document) { document.encode(Encoding::Shift_JIS).b }

    assert_equal "application/rss+xml", detect(sjis.(%(<?xml version="1.0" encoding="Shift_JIS"?><rss ソ="1"/>)))
    assert_equal "application/rss+xml", detect(sjis.(%(<?xml version="1.0" encoding="Shift_JIS"?><rss note="ソ"/>)))
    assert_equal "application/rss+xml", detect(sjis.(%(<?xml version="1.0" encoding="Shift_JIS"?><!DOCTYPE rss [<!-- ‐ -->]><rss/>)))
    assert_equal "application/rss+xml", detect(sjis.(%(<?xml version="1.0" encoding="Shift_JIS"?><!-- ソ --><rss/>)))

    # Bytes invalid in the declared encoding stay fatal before the root and harmless after.
    assert_equal "application/xml", detect(%(<?xml version="1.0" encoding="Shift_JIS"?><rss note="\x82"/>).b)
    assert_equal "application/rss+xml", detect(%(<?xml version="1.0" encoding="Shift_JIS"?><rss/>).b + "\x82".b)
  end

  test "declared US-ASCII rejects high bytes before the root and ignores them after" do
    assert_equal "application/rss+xml", detect(%(<?xml version="1.0" encoding="US-ASCII"?><rss/>))
    assert_equal "application/xml", detect(%(<?xml version="1.0" encoding="US-ASCII"?><!-- caf\xE9 --><rss/>).b)
    assert_equal "application/rss+xml", detect(%(<?xml version="1.0" encoding="US-ASCII"?><rss/>).b + "\xE9".b)
  end

  test "a legacy multibyte character split by the scan limit is harmless after the root" do
    document = %(<?xml version="1.0" encoding="Shift_JIS"?><rss/>).b
    document << "x" * (Marcel::Magic::Xml::MAX_SCAN - document.bytesize - 1) << "ソ".encode(Encoding::Shift_JIS).b

    assert_operator document.bytesize, :>, Marcel::Magic::Xml::MAX_SCAN
    assert_equal "application/rss+xml", detect(document)
  end

  test "encoding is validated only over the bytes consumed up to the root start-tag" do
    assert_equal "application/rss+xml", detect(xml("<rss version=\"2.0\"><!-- \xFF --></rss>".b))

    split_pair = "﻿#{xml('<rss/>')}\u{1F600}".encode(Encoding::UTF_16LE).b
    assert_equal "application/rss+xml", detect(split_pair.byteslice(0, split_pair.bytesize - 2))
    assert_equal "application/rss+xml", detect("﻿#{xml("<!-- \u{1F600} --><rss/>")}".encode(Encoding::UTF_16BE).b)
  end

  test "prolog markup a SAX parser rejects keeps the generic type" do
    assert_equal "application/xml", detect(%(<?XML version="1.0"?><rss/>))
    assert_equal "application/xml", detect(%(<?xml encoding="UTF-8"?><rss/>))
    assert_equal "application/xml", detect(%(<?xml version="1.0"?><?xml version="1.0"?><rss/>))
    assert_equal "application/xml", detect(%(<!-- first -->#{DECLARATION}<rss/>))
    assert_equal "application/rss+xml", detect(xml("<?XmL-ish only the exact xml target is reserved?><rss/>"))
    assert_equal "application/xml", detect(xml("<!-- a -- b --><rss/>"))
    assert_equal "application/xml", detect(xml("<!-- ends with hyphen ---><rss/>"))
    assert_equal "application/xml", detect(xml("<!DOCTYPE rss [ <!-- a -- b --> ]><rss/>"))
    assert_equal "application/rss+xml", detect(xml("<?xml-stylesheet href=\"s.xsl\"?><rss/>"))
  end

  test "the XML declaration is parsed in full, not by prefix" do
    # Trailing or duplicated declaration tokens must not hide behind the PI skipper.
    assert_equal "application/xml", detect(%(<?xml version="1.0" garbage?><rss/>))
    assert_equal "application/xml", detect(%(<?xml version="1.0"garbage?><rss/>))
    assert_equal "application/xml", detect(%(<?xml version="1.0" standalone="maybe"?><rss/>))
    assert_equal "application/xml", detect(%(<?xml version="1.0" encoding="UTF-8" encoding="Shift_JIS"?><rss/>))
    assert_equal "application/xml", detect(%(<?xml version="1.0" standalone="no" encoding="UTF-8"?><rss/>))

    assert_equal "application/rss+xml", detect(%(<?xml version="1.0" standalone="yes"?><rss/>))
    assert_equal "application/rss+xml", detect(%(<?xml version="1.0" encoding="UTF-8" standalone="no"?><rss/>))
    assert_equal "application/rss+xml", detect(%(<?xml version = "1.0" ?><rss/>))
  end

  test "duplicate attributes on the root refine nothing" do
    # A well-formedness fatal error in SAX; last-one-wins could otherwise flip the namespace.
    assert_equal "application/xml", detect(xml('<rss xmlns="urn:not-rss" xmlns="" version="2.0"/>'))
    assert_equal "application/xml", detect(xml('<feed xmlns="http://www.w3.org/2005/Atom" xmlns="http://www.w3.org/2005/Atom"/>'))
    assert_equal "application/xml", detect(xml('<k:kml xmlns:k="http://www.opengis.net/kml/2.2" xmlns:k="http://www.opengis.net/kml/2.2"/>'))
  end

  test "namespace-aware attribute validation matches SAX" do
    # Two prefixes for one namespace expand to duplicate [namespace, local] attribute
    # names; unbound prefixes, malformed QNames and a raw < in a value are equally fatal
    # to a namespace-aware parser before it reports the root.
    assert_equal "application/xml", detect(xml('<rss xmlns:a="urn:x" xmlns:b="urn:x" a:x="1" b:x="2"/>'))
    assert_equal "application/xml", detect(xml('<rss p:x="1"/>'))
    assert_equal "application/xml", detect(xml('<rss a:b:c="1"/>'))
    assert_equal "application/xml", detect(xml('<rss note="a<b"/>'))

    assert_equal "application/rss+xml", detect(xml('<rss xmlns:a="urn:x" xmlns:b="urn:y" a:x="1" b:x="2"/>'))
    assert_equal "application/rss+xml", detect(xml('<rss xml:lang="en" version="2.0"/>'))
  end

  test "reserved xml and xmlns bindings are enforced" do
    assert_equal "application/xml", detect(xml('<rss xmlns:xml="urn:x"/>'))
    assert_equal "application/xml", detect(xml('<rss xmlns:xmlns="urn:x"/>'))
    assert_equal "application/xml", detect(xml('<rss xmlns:a="http://www.w3.org/XML/1998/namespace"/>'))
    assert_equal "application/xml", detect(xml('<rss xmlns="http://www.w3.org/2000/xmlns/"/>'))
    assert_equal "application/xml", detect(xml('<rss xmlns:a=""/>'))

    assert_equal "application/rss+xml", detect(xml('<rss xmlns:xml="http://www.w3.org/XML/1998/namespace"/>'))
  end

  test "malformed references in attribute values refine nothing" do
    assert_equal "application/xml", detect(xml('<rss note="a&b"/>'))
    assert_equal "application/xml", detect(xml('<rss note="a&#xZZ;b"/>'))

    assert_equal "application/rss+xml", detect(xml('<rss note="a&amp;b"/>'))
    assert_equal "application/rss+xml", detect(xml('<rss note="&#65;&#x41;"/>'))
  end

  test "processing instruction data must be separated from its target by whitespace" do
    assert_equal "application/xml", detect(xml("<?pi?x?><rss/>"))

    assert_equal "application/rss+xml", detect(xml("<?pi?><rss/>"))
    assert_equal "application/rss+xml", detect(xml("<?pi data?><rss/>"))
  end

  test "only SAX-supported XML versions are recognized" do
    assert_equal "application/xml", detect(%(<?xml version="1.9"?><rss/>))

    assert_equal "application/rss+xml", detect(%(<?xml version="1.1"?><rss/>))
  end

  test "characters the XML version forbids as literals refine nothing wherever they fall" do
    assert_equal "application/xml", detect(xml("<!-- \x00 --><rss/>"))
    assert_equal "application/xml", detect(xml(%(<rss note="a\x01b"/>)))
    assert_equal "application/xml", detect(xml("<!-- \x01 --><rss/>"))

    # XML 1.1 restricts the C0 and C1 controls to character references; XML 1.0 forbids
    # C0 outright but admits literal C1. Comments may contain a raw < under both.
    assert_equal "application/xml", detect(%(<?xml version="1.1"?><!-- \x01 --><rss/>))
    assert_equal "application/xml", detect(%(<?xml version="1.1"?><!-- \u0080 --><rss/>))
    assert_equal "application/rss+xml", detect(xml("<!-- \u0080 --><rss/>"))
    assert_equal "application/rss+xml", detect(xml("<!-- a < b --><rss/>"))
  end

  test "character references must denote characters the XML version admits" do
    assert_equal "application/xml", detect(xml('<rss note="&#1;"/>'))
    assert_equal "application/xml", detect(%(<?xml version="1.1"?><rss note="&#0;"/>))
    assert_equal "application/xml", detect(xml('<rss note="&#xD800;"/>'))
    assert_equal "application/xml", detect(xml('<rss note="&#x110000;"/>'))
    assert_equal "application/xml", detect(xml('<rss note="&#xFFFE;"/>'))

    # XML 1.1 admits as references the controls it forbids as literals.
    assert_equal "application/rss+xml", detect(%(<?xml version="1.1"?><rss note="&#1;"/>))
    assert_equal "application/rss+xml", detect(xml('<rss note="&#x10FFFF;"/>'))
  end

  test "character references admit unlimited leading zeros" do
    # The CharRef grammar has no digit cap; only the significant digits are bounded, and
    # the scalar they denote must still be one the XML version admits.
    assert_equal "application/rss+xml", detect(xml('<rss note="&#00000009;"/>'))
    assert_equal "application/rss+xml", detect(xml('<rss note="&#x000000041;"/>'))
    assert_equal "application/rss+xml", detect(%(<?xml version="1.1"?><rss note="&#00000001;"/>))

    assert_equal "application/xml", detect(xml('<rss note="&#00000001;"/>'))
    assert_equal "application/xml", detect(xml('<rss note="&#00000000;"/>'))
    assert_equal "application/xml", detect(%(<?xml version="1.1"?><rss note="&#x0000;"/>))
    assert_equal "application/xml", detect(xml('<rss note="&#000000000000001114112;"/>'))
    assert_equal "application/xml", detect(xml('<rss note="&#99999999999999999999;"/>'))
    assert_equal "application/xml", detect(xml('<rss note="&#x00110000;"/>'))
  end

  test "PI targets and entity names admit the full XML Name grammar, colon included" do
    # Namespace processing claims the colon in QNames and prefixes only; a namespace-aware
    # SAX parser accepts it in a PI target or an entity name.
    assert_equal "application/rss+xml", detect(xml("<?p:x?><rss/>"))
    assert_equal "application/rss+xml",
      detect(xml(%(<!DOCTYPE rss [<!ENTITY p:x "y">]>\n<rss note="&p:x;"/>)))

    assert_equal "application/xml", detect(xml('<rss note="&p:x;"/>'))
  end

  test "entity references must be predefined unless a DTD could have declared them" do
    assert_equal "application/xml", detect(xml('<rss note="&nbsp;"/>'))

    assert_equal "application/rss+xml", detect(xml('<rss note="&quot;&apos;&lt;&gt;&amp;"/>'))
    assert_equal "application/rss+xml",
      detect(xml(%(<!DOCTYPE rss [<!ENTITY nbsp "&#xA0;">]>\n<rss note="&nbsp;"/>)))
  end

  test "names are validated as Unicode names, not as arbitrary high bytes" do
    # U+00B7 is NameChar but not NameStartChar, while U+00E9 starts a name.
    assert_equal "application/xml", detect(xml(%(<rss ·note="1"/>)))
    assert_equal "application/xml", detect(xml(%(<rss xmlns:·p="urn:x"/>)))
    assert_equal "application/xml", detect(xml("<·rss/>"))
    assert_equal "application/xml", detect(xml("<?·pi ?><rss/>"))
    assert_equal "application/xml", detect(xml(%(<rss note="&·e;"/>)))

    assert_equal "application/rss+xml", detect(xml(%(<rss café="1"/>)))
    assert_equal "application/rss+xml", detect(xml("<?café-pi ?><rss/>"))
  end

  test "XML 1.1 permits prefix undeclaration where 1.0 does not" do
    assert_equal "application/rss+xml", detect(%(<?xml version="1.1"?><rss xmlns:p=""/>))

    assert_equal "application/xml", detect(xml('<rss xmlns:p=""/>'))
    assert_equal "application/xml", detect(%(<?xml version="1.1"?><p:rss xmlns:p=""/>))
    assert_equal "application/xml", detect(%(<?xml version="1.1"?><rss xmlns:xml=""/>))
  end

  test "unseekable but rewindable IOs are refined" do
    assert_equal "application/rss+xml", Marcel::MimeType.for(UnseekableIO.new(xml('<rss version="2.0"/>')))
  end

  test "empty and whitespace-only content is untouched" do
    assert_equal "application/octet-stream", detect("")
    assert_equal "application/octet-stream", detect("   \n")
  end

  test "only the generic XML type is refined" do
    assert_equal "application/zip", Marcel::Magic::Xml.refine(StringIO.new(xml('<rss/>')), "application/zip")
    assert_equal "text/html", Marcel::Magic::Xml.refine(StringIO.new(xml('<rss/>')), "text/html")
  end

  test "a large document is scanned within its bounded prefix" do
    io = CountingIO.new(DECLARATION + "<!--" + ("x" * 10 * 1024 * 1024) + "--><rss/>")

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_equal "application/xml", Marcel::Magic::Xml.refine(io, "application/xml")
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at, :<, 1.0
    assert_equal Marcel::Magic::Xml::MAX_SCAN, io.bytes_read
  end

  test "adversarial prologs give up in bounded time" do
    quotes = xml("<!DOCTYPE r [" + (%('"') * 20_000) + ("<!--" * 5_000))
    pis = xml("<?a?>" * 10_000 + "<!DOCTYPE r [" + ("<?b ]>" * 5_000))

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_equal "application/xml", detect(quotes)
    assert_equal "application/xml", detect(pis)
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at, :<, 1.0
  end

  test "a filename refines generic XML content to a feed type" do
    assert_equal "application/rss+xml", detect(xml('<root/>'), name: "feed.rss")
    assert_equal "application/atom+xml", detect(xml('<root/>'), name: "feed.atom")
    assert_equal "application/xslt+xml", detect(xml('<root/>'), declared_type: "application/xslt+xml")
  end

  test "content-detected feed types are not overridden by a conflicting sibling hint" do
    assert_equal "application/rss+xml", detect(xml('<rss version="2.0"/>'), name: "feed.atom")
    assert_equal "application/rss+xml", detect(xml('<rss version="2.0"/>'), name: "feed.xml")
  end

  test "existing XML-flavoured fixtures keep their types" do
    assert_equal "application/xml", Marcel::MimeType.for(files("magic/application/xml/xml.xml"))
    assert_equal "image/svg+xml", Marcel::MimeType.for(files("magic/image/svg+xml/svg_with_comment.svg"))
    assert_equal "text/html", Marcel::MimeType.for(files("magic/text/html/html_with_leading_comment.html"))
  end

  test "refine leaves the IO rewound" do
    io = StringIO.new(xml('<rss version="2.0"/>'))

    Marcel::MimeType.for(io)
    assert_equal 0, io.pos
  end
end
