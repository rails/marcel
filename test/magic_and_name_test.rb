require 'test_helper'
require 'rack'

class Marcel::MimeType::MagicAndNameTest < Marcel::TestCase
  # All fixtures that can be recognised by name should also be recognisable when given
  # the file contents and the name. In some cases, the file contents will point to a
  # generic type, while the name will choose a more specific subclass
  each_content_type_fixture('name') do |file, name, content_type|
    test "correctly returns #{content_type} for #{name} given both file and name" do
      assert_equal content_type, Marcel::MimeType.for(file, name: name)
    end
  end
end
