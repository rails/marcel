require 'test_helper'
require 'rack'

class Marcel::ContentType::MagicTest < ActiveSupport::TestCase
  each_content_type_fixture('magic') do |file, name, content_type|
    test "gets type for #{content_type} by using magic bytes #{name}" do
      assert_equal content_type, Marcel::ContentType.for(file)
    end
  end
end
