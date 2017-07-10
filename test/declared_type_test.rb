require 'test_helper'
require 'rack'

class Marcel::MimeType::DeclaredTypeTest < Marcel::TestCase
  test "returns declared type as last resort" do
    assert_equal "text/html", Marcel::MimeType.for(name: "unrecognisable", declared_type: "text/html")
  end

  test "returns application/octet-stream if declared type empty or unrecognised" do
    assert_equal "application/octet-stream", Marcel::MimeType.for(declared_type: "")
    assert_equal "application/octet-stream", Marcel::MimeType.for(declared_type: "unrecognised")
  end

  test "ignores charset declarations" do
    assert_equal "text/html", Marcel::MimeType.for(declared_type: "text/html; charset=utf-8")
  end
end
