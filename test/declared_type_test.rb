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

  test "resolves declared type to a canonical MIME type" do
    aliased, canonical = Marcel::TYPE_ALIASES.first
    assert_equal canonical, Marcel::MimeType.for(declared_type: aliased)
  end
end
