require 'test_helper'
require 'rack'

class Marcel::MimeType::NameTest < Marcel::TestCase
  test "ignores invalidly encoded filename extensions without raising" do
    invalid_name = "file.html\xFF".dup.force_encoding(Encoding::UTF_8)

    assert_nil Marcel::Magic.by_path(invalid_name)
    assert_equal "application/octet-stream", Marcel::MimeType.for(name: invalid_name)
  end

  test "uses a valid extension after an invalidly encoded basename" do
    name = "file\xFF.html".dup.force_encoding(Encoding::UTF_8)

    assert_equal "text/html", Marcel::MimeType.for(name: name)
  end

  test "ignores filenames that cannot be parsed as paths" do
    invalid_names = [
      "file.html\0.pdf",
      "file.html".encode(Encoding::UTF_16LE),
    ]

    invalid_names.each do |invalid_name|
      assert_nil Marcel::Magic.by_path(invalid_name)
      assert_equal "application/octet-stream", Marcel::MimeType.for(name: invalid_name)
    end
  end

  each_content_type_fixture('name') do |file, name, content_type|
    test "gets type for #{content_type} by filename from #{name}" do
      assert_equal content_type, Marcel::MimeType.for(name: name)
    end
  end
end
