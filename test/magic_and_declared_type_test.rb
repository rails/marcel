require 'test_helper'
require 'rack'

class Marcel::ContentType::MagicAndDeclaredTypeTest < ActiveSupport::TestCase
  each_content_type_fixture('name') do |file, name, content_type|
    test "correctly returns #{content_type} for #{name} given both file and declared type" do
      assert_equal content_type, Marcel::ContentType.for(file, declared_type: content_type)
    end
  end
end
