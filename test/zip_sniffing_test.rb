require 'test_helper'
require 'zlib'

class Marcel::MimeType::ZipSniffingTest < Marcel::TestCase
  # An IO that supports sequential reads but neither seek nor size, like a
  # non-rewindable pipe wrapper.
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

  OOXML_CONTENT_TYPES = <<~XML
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>
  XML

  # Builds a valid ZIP archive in memory with stored (uncompressed) entries.
  def zip_archive(entries, zip64: false)
    io = StringIO.new(String.new(encoding: Encoding::BINARY))
    directory = String.new(encoding: Encoding::BINARY)

    entries.each do |name, data|
      data = (data || "").b
      offset = io.pos
      crc = Zlib.crc32(data)

      header = [20, 0, 0, 0, 0, crc, data.bytesize, data.bytesize, name.bytesize, 0].pack("v5V3v2")
      io << "PK\x03\x04".b << header << name.b << data

      central = [20, 20, 0, 0, 0, 0, crc, data.bytesize, data.bytesize,
                 name.bytesize, 0, 0, 0, 0, 0, offset].pack("v6V3v5V2")
      directory << "PK\x01\x02".b << central << name.b
    end

    directory_offset = io.pos
    io << directory

    if zip64
      zip64_eocd_offset = io.pos
      io << "PK\x06\x06".b << [44, 45, 45, 0, 0, entries.size, entries.size,
                               directory.bytesize, directory_offset].pack("Q<v2V2Q<4")
      io << "PK\x06\x07".b << [0, zip64_eocd_offset, 1].pack("VQ<V")
      io << "PK\x05\x06".b << [0, 0, 0xFFFF, 0xFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0].pack("v4V2v")
    else
      io << "PK\x05\x06".b << [0, 0, entries.size, entries.size,
                               directory.bytesize, directory_offset, 0].pack("v4V2v")
    end

    io.string
  end

  def xlsx_parts
    { "[Content_Types].xml" => OOXML_CONTENT_TYPES, "_rels/.rels" => "", "xl/workbook.xml" => "<workbook/>" }
  end

  test "spreadsheet with [Content_Types].xml past the 64KB magic ceiling is detected from content" do
    data = zip_archive({ "docProps/padding.bin" => "\0" * 80_000 }.merge(xlsx_parts))

    assert_operator data.index("[Content_Types].xml"), :>, 65_536
    assert_equal "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      Marcel::MimeType.for(StringIO.new(data))
  end

  test "word document past the 64KB magic ceiling is detected from content" do
    data = zip_archive({ "docProps/padding.bin" => "\0" * 80_000,
                         "[Content_Types].xml" => OOXML_CONTENT_TYPES,
                         "word/document.xml" => "<document/>" })

    assert_equal "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      Marcel::MimeType.for(StringIO.new(data))
  end

  test "presentation past the 64KB magic ceiling is detected from content" do
    data = zip_archive({ "docProps/padding.bin" => "\0" * 80_000,
                         "[Content_Types].xml" => OOXML_CONTENT_TYPES,
                         "ppt/presentation.xml" => "<presentation/>" })

    assert_equal "application/vnd.openxmlformats-officedocument.presentationml.presentation",
      Marcel::MimeType.for(StringIO.new(data))
  end

  test "macro-enabled workbook is detected from content alone" do
    data = zip_archive(xlsx_parts.merge("xl/vbaProject.bin" => "\x01\x02"))

    assert_equal "application/vnd.ms-excel.sheet.macroenabled.12",
      Marcel::MimeType.for(StringIO.new(data))
  end

  test "macro-enabled word document is detected from content alone" do
    data = zip_archive({ "[Content_Types].xml" => OOXML_CONTENT_TYPES,
                         "word/document.xml" => "<document/>", "word/vbaProject.bin" => "\x01\x02" })

    assert_equal "application/vnd.ms-word.document.macroenabled.12",
      Marcel::MimeType.for(StringIO.new(data))
  end

  test "macro-enabled presentation is detected from content alone" do
    data = zip_archive({ "[Content_Types].xml" => OOXML_CONTENT_TYPES,
                         "ppt/presentation.xml" => "<presentation/>", "ppt/vbaProject.bin" => "\x01\x02" })

    assert_equal "application/vnd.ms-powerpoint.presentation.macroenabled.12",
      Marcel::MimeType.for(StringIO.new(data))
  end

  test "macro-enabled template keeps its name-derived type over the content-derived macro type" do
    data = zip_archive(xlsx_parts.merge("xl/vbaProject.bin" => "\x01\x02"))

    assert_equal "application/vnd.ms-excel.template.macroenabled.12",
      Marcel::MimeType.for(StringIO.new(data), name: "template.xltm")
  end

  test "macro-enabled content wins over a non-macro filename" do
    data = zip_archive(xlsx_parts.merge("xl/vbaProject.bin" => "\x01\x02"))

    assert_equal "application/vnd.ms-excel.sheet.macroenabled.12",
      Marcel::MimeType.for(StringIO.new(data), name: "innocent.xlsx")
  end

  test "zip64 archives are refined via the zip64 end-of-central-directory record" do
    data = zip_archive({ "docProps/padding.bin" => "\0" * 80_000 }.merge(xlsx_parts), zip64: true)

    assert_equal "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      Marcel::MimeType.for(StringIO.new(data))
  end

  test "plain zips are not upgraded" do
    data = zip_archive({ "hello.txt" => "hello", "world/notes.txt" => "notes" })

    assert_equal "application/zip", Marcel::MimeType.for(StringIO.new(data))
  end

  test "truncated archives keep the base type without raising" do
    data = zip_archive({ "docProps/padding.bin" => "\0" * 80_000 }.merge(xlsx_parts))

    assert_equal "application/zip", Marcel::MimeType.for(StringIO.new(data[0...-10]))
  end

  test "corrupt central directory keeps the base type without raising" do
    data = zip_archive(xlsx_parts)
    corrupted = data.dup.tap { |d| d[d.index("PK\x01\x02"), 4] = "XXXX" }

    assert_equal "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      Marcel::MimeType.for(StringIO.new(corrupted))
  end

  test "partial reads keep prefix-based detection without raising" do
    data = zip_archive(xlsx_parts)

    assert_equal "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      Marcel::MimeType.for(StringIO.new(data[0, 4096]))
  end

  test "partial reads of padded archives keep the base type without raising" do
    data = zip_archive({ "docProps/padding.bin" => "\0" * 80_000 }.merge(xlsx_parts))

    assert_equal "application/zip", Marcel::MimeType.for(StringIO.new(data[0, 4096]))
  end

  test "unseekable IOs keep the base type without raising" do
    data = zip_archive(xlsx_parts.merge("xl/vbaProject.bin" => "\x01\x02"))

    assert_equal "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      Marcel::MimeType.for(UnseekableIO.new(data))
  end

  test "adversarial comment full of EOCD signatures gives up in bounded time" do
    data = zip_archive(xlsx_parts) + ("PK\x05\x06" * 20_000).b

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_equal "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      Marcel::MimeType.for(StringIO.new(data))
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at, :<, 1.0
  end

  test "existing OOXML fixtures still refine to their own types" do
    { "vnd.openxmlformats-officedocument.spreadsheetml.sheet" => "xlsx",
      "vnd.openxmlformats-officedocument.wordprocessingml.document" => "docx",
      "vnd.openxmlformats-officedocument.presentationml.presentation" => "pptx" }.each do |type, extension|
      fixture = files("magic/application/#{type}/#{type}.#{extension}")
      assert_equal "application/#{type}", Marcel::MimeType.for(fixture)
    end
  end

  test "refine leaves the IO rewound" do
    data = zip_archive(xlsx_parts)
    io = StringIO.new(data)

    Marcel::MimeType.for(io)
    assert_equal 0, io.pos
  end
end
