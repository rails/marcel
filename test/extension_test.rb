require 'test_helper'
require 'rack'

class Marcel::MimeType::ExtensionTest < ActiveSupport::TestCase
  test "ignores case and any preceding dot" do
    assert_equal "application/pdf", Marcel::MimeType.for(extension: "PDF")
    assert_equal "application/pdf", Marcel::MimeType.for(extension: ".PDF")
    assert_equal "application/pdf", Marcel::MimeType.for(extension: "pdf")
    assert_equal "application/pdf", Marcel::MimeType.for(extension: ".pdf")
  end

  each_content_type_fixture('name') do |file, name, content_type|
    extension = File.extname(name)

    test "gets type for #{content_type} given file extension #{extension}" do
      assert_equal content_type, Marcel::MimeType.for(extension: extension)
    end
  end
end
