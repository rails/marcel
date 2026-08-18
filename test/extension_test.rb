require 'test_helper'
require 'rack'

class Marcel::MimeType::ExtensionTest < Marcel::TestCase
  test "ignores case and any preceding dot" do
    assert_equal "application/pdf", Marcel::MimeType.for(extension: "PDF")
    assert_equal "application/pdf", Marcel::MimeType.for(extension: ".PDF")
    assert_equal "application/pdf", Marcel::MimeType.for(extension: "pdf")
    assert_equal "application/pdf", Marcel::MimeType.for(extension: ".pdf")
  end

  test "ignores invalidly encoded extensions without raising" do
    invalid_extension = "html\xFF".dup.force_encoding(Encoding::UTF_8)

    assert_nil Marcel::Magic.by_extension(invalid_extension)
    assert_equal "application/octet-stream", Marcel::MimeType.for(extension: invalid_extension)
  end

  test "preserves valid custom non-ASCII extensions" do
    type = "application/x-unicode-extension"
    Marcel::Magic.add(type, extensions: "éx")

    assert_equal type, Marcel::MimeType.for(extension: "ÉX")
  ensure
    Marcel::Magic.remove(type)
  end

  extensions = []

  each_content_type_fixture('name') do |file, name, content_type|
    extension = File.extname(name)

    unless extensions.include?(extension)
      test "gets type for #{content_type} given file extension #{extension}" do
        assert_equal content_type, Marcel::MimeType.for(extension: extension)
      end

      extensions << extension
    end
  end
end
