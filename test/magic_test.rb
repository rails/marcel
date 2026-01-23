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

  test "no Ruby 3.4 frozen string warnings with StringIO" do
    # Ruby 3.4 warns about code that will break when frozen string literals become default
    # This test ensures marcel handles StringIO with frozen strings correctly
    content = "Test content for mime detection"
    io = StringIO.new(content)

    # Capture warnings
    warnings = []
    original_stderr = $stderr
    $stderr = StringIO.new

    begin
      Marcel::MimeType.for(io)
      warnings = $stderr.string.lines.grep(/marcel.*magic\.rb.*frozen/)
    ensure
      $stderr = original_stderr
    end

    assert_empty warnings, "Expected no frozen string warnings, but got:\n#{warnings.join}"
  end
end
