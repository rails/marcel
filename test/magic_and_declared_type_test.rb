require 'test_helper'
require 'rack'

class Marcel::MimeType::MagicAndDeclaredTypeTest < Marcel::TestCase
  each_content_type_fixture('name') do |file, name, content_type|
    test "detects #{content_type} given magic bytes from #{name} and declared type" do
      assert_equal content_type, Marcel::MimeType.for(file, declared_type: content_type)
    end

    ALIASED[content_type].each do |aliased|
      test "detects #{content_type} given magic bytes from #{name} and aliased type #{aliased}" do
        assert_equal content_type, Marcel::MimeType.for(file, declared_type: aliased)
      end
    end
  end
end
