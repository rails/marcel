require 'test_helper'
require 'rack'

class Marcel::MimeType::MagicTest < Marcel::TestCase
  # These fixtures should be recognisable given only their contents. Where a generic type
  # has more specific subclasses (such as application/zip), these subclasses cannot usually
  # be recognised by magic alone; their name is also needed to correctly identify them.
  each_content_type_fixture('magic') do |file, name, content_type|
    test "gets type for #{content_type} by using only magic bytes #{name}" do
      assert_equal content_type, Marcel::MimeType.for(file)
    end
  end

  test "add and remove type" do
    Marcel::Magic.add('application/x-my-thing', extensions: 'mtg', parents: 'application/json')
    Marcel::Magic.remove('application/x-my-thing')
  end

  test "#extensions" do
    json = Marcel::Magic.by_extension('json')
    assert_equal ['json'], json.extensions
  end

  test ".child?" do
    assert Marcel::Magic.child?('text/csv', 'text/plain')
    refute Marcel::Magic.child?('text/plain', 'text/csv')
  end
end
