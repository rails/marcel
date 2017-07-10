require 'test_helper'
require 'rack'

class Marcel::MimeType::NameTest < Marcel::TestCase
  each_content_type_fixture('name') do |file, name, content_type|
    test "gets type for #{content_type} by filename from #{name}" do
      assert_equal content_type, Marcel::MimeType.for(name: name)
    end
  end
end
