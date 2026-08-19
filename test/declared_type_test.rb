require 'test_helper'
require 'rack'

class Marcel::MimeType::DeclaredTypeTest < Marcel::TestCase
  test "prefers declared type over filename extension" do
    assert_equal "text/html", Marcel::MimeType.for(name: "file.txt", declared_type: "text/html")
  end

  test "prefers filename extension over binary type" do
    assert_equal "text/plain", Marcel::MimeType.for(name: "file.txt", declared_type: "application/octet-stream")
  end

  test "defaults to binary if declared type is unrecognized" do
    assert_equal "application/octet-stream", Marcel::MimeType.for(declared_type: nil)
    assert_equal "application/octet-stream", Marcel::MimeType.for(declared_type: "")
    assert_equal "application/octet-stream", Marcel::MimeType.for(declared_type: "unrecognised")
  end

  test "ignores charset declarations" do
    assert_equal "text/html", Marcel::MimeType.for(declared_type: "text/html; charset=utf-8")
  end

  test "tolerates a single trailing semicolon" do
    assert_equal "image/jpeg", Marcel::MimeType.for(declared_type: "image/jpeg;")
    assert_equal "text/html", Marcel::MimeType.for(declared_type: "text/html; charset=utf-8; ")
  end

  test "normalizes case and surrounding HTTP whitespace" do
    assert_equal "text/html", Marcel::MimeType.for(declared_type: " \tTEXT/HTML\r\n")
    assert_equal "text/html", Marcel::MimeType.for(name: "file.txt", declared_type: " text/html")
  end

  test "accepts valid media type tokens" do
    assert_equal "application/vnd.example+json", Marcel::MimeType.for(declared_type: "APPLICATION/VND.EXAMPLE+JSON")
  end

  test "allows commas in quoted parameters" do
    assert_equal "text/html", Marcel::MimeType.for(declared_type: 'text/html; example="one,two"')
    assert_equal "text/html", Marcel::MimeType.for(declared_type: 'text/html; example="one\",two"')
  end

  test "ignores malformed media types" do
    malformed_types = [
      "/html",
      "text/",
      "text/ html",
      "text/html garbage",
      "text/html\0garbage",
      "text/html/extra",
      "text/{html",
      "t\u00EBxt/html",
      "\vtext/html",
      "\ftext/html",
      "text/html;;charset=utf-8",
      "text/html; ; charset=utf-8",
      "text/html; example=foo\", image/png\"",
      "text/html; example=\"unterminated",
      "text/html; example=foo\0bar",
    ]

    malformed_types.each do |declared_type|
      assert_equal "application/octet-stream", Marcel::MimeType.for(declared_type: declared_type),
        "Expected #{declared_type.inspect} to be ignored"
      assert_equal "text/plain", Marcel::MimeType.for(name: "file.txt", declared_type: declared_type),
        "Expected #{declared_type.inspect} to fall back to the filename"
    end
  end

  test "ignores comma-separated media type lists" do
    ["text/html, image/png", "image/png, text/html", "invalid, text/html"].each do |declared_type|
      assert_equal "application/octet-stream", Marcel::MimeType.for(declared_type: declared_type),
        "Expected #{declared_type.inspect} to be ignored"
      assert_equal "text/plain", Marcel::MimeType.for(name: "file.txt", declared_type: declared_type),
        "Expected #{declared_type.inspect} to fall back to the filename"
    end
  end

  test "normalizes binary type before treating it as undeclared" do
    assert_equal "text/plain", Marcel::MimeType.for(
      name: "file.txt", declared_type: " \tAPPLICATION/OCTET-STREAM ; example=value\r\n"
    )
  end

  test "ignores invalidly encoded declared types without raising" do
    invalid_type = "text/html\xFF".dup.force_encoding(Encoding::UTF_8)

    assert_equal "application/octet-stream", Marcel::MimeType.for(declared_type: invalid_type)
    assert_equal "text/plain", Marcel::MimeType.for(name: "file.txt", declared_type: invalid_type)
  end

  test "returns well-formed unknown declared types as UTF-8 labels" do
    result = Marcel::MimeType.for(name: "file.html", declared_type: "APPLICATION/X-EVIL")

    assert_equal "application/x-evil", result
    assert_equal Encoding::UTF_8, result.encoding
  end

  test "bounds declared type metadata" do
    prefix = "application/"
    maximum = prefix + ("a" * (Marcel::MimeType::MAX_DECLARED_TYPE_BYTES - prefix.bytesize))
    oversized = maximum + "a"

    assert_equal maximum, Marcel::MimeType.for(declared_type: maximum)
    assert_equal "application/octet-stream", Marcel::MimeType.for(declared_type: oversized)
    assert_equal "text/plain", Marcel::MimeType.for(name: "file.txt", declared_type: oversized)
  end
end
