require 'test_helper'
require 'rack'

class Marcel::MimeType::DeclaredTypeTest < ActiveSupport::TestCase
  test "returns declared type as last resort" do
    assert_equal "text/html", Marcel::MimeType.for(name: "unrecognisable", declared_type: "text/html")
  end

  test "ignores charset declarations" do
    assert_equal "text/html", Marcel::MimeType.for(declared_type: "text/html; charset=utf-8")
  end
end
