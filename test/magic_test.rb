require 'test_helper'
require 'rack'

class Marcel::MimeType::MagicTest < ActiveSupport::TestCase
  each_content_type_fixture('magic') do |file, name, content_type|
    test "gets type for #{content_type} by using magic bytes #{name}" do
      assert_equal content_type, Marcel::MimeType.for(file)
    end
  end
end
