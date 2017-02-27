require 'test_helper'
require 'rack'

class Marcel::MimeType::NameTest < ActiveSupport::TestCase
  extensions = {}

  each_content_type_fixture('name') do |file, name, content_type|
    extensions[File.extname(name)] = content_type

    test "gets type for #{content_type} by filename from #{name}" do
      assert_equal content_type, Marcel::MimeType.for(nil, name: name)
    end
  end

  extensions.each do |(extension, content_type)|
    test "gets type for #{content_type} given file extension #{extension}" do
      assert_equal content_type, Marcel::MimeType.for_extension(extension)
      assert_equal content_type, Marcel::MimeType.for_extension(extension.downcase)
      assert_equal content_type, Marcel::MimeType.for_extension(extension[1..-1])
      assert_equal content_type, Marcel::MimeType.for_extension(extension[1..-1].downcase)
    end
  end
end
