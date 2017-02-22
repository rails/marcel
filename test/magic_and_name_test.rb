require 'test_helper'
require 'rack'

class Marcel::ContentType::MagicAndNameTest < ActiveSupport::TestCase
  each_content_type_fixture('name') do |file, name, content_type|
    test "correctly returns #{content_type} for #{name} given both file and name" do
      assert_equal content_type, Marcel::ContentType.for(file, name: name)
    end
  end
end
