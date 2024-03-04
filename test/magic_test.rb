require 'test_helper'
require 'rack'

class Marcel::MimeType::MagicTest < Marcel::TestCase
  # These fixtures should be recognisable given only their contents. Where a generic type
  # has more specific subclasses (such as application/zip), these subclasses cannot usually
  # be recognised by magic alone; their name is also needed to correctly identify them.
  each_content_type_fixture('magic') do |file, name, content_type|
    test "detects #{content_type} given magic bytes from #{name}" do
      assert_equal content_type, Marcel::MimeType.for(file)
    end
  end

  test "switch canonical type" do
    Marcel::Magic.add('canonical/type', aliases: 'alias/type', extensions: %w[ canonical ], parents: 'canonical/parent', magic: [[0, 'magic']])
    assert Marcel::Magic.child?('canonical/type', 'canonical/parent')
    assert_equal 'canonical/type', Marcel::Magic.canonical('alias/type')
    assert_equal 'canonical/type', Marcel::Magic.by_extension('canonical').type
    assert_equal 'canonical/type', Marcel::Magic.by_magic('magic').type

    Marcel::Magic.canonicalize('alias/type', instead_of: 'canonical/type')
    assert Marcel::Magic.child?('alias/type', 'canonical/parent')
    assert_equal 'alias/type', Marcel::Magic.canonical('alias/type')
    assert_equal 'alias/type', Marcel::Magic.canonical('canonical/type')
    assert_equal 'alias/type', Marcel::Magic.by_extension('canonical').type
    assert_equal 'alias/type', Marcel::Magic.by_magic('magic').type
  end

  test "add and remove type" do
    Marcel::Magic.add('application/x-my-thing', extensions: 'mtg', parents: 'application/json')
    Marcel::Magic.remove('application/x-my-thing')
  end

  test "removing alias" do
    Marcel::Magic.add('canonical/type', aliases: 'alias/type')
    assert_equal 'canonical/type', Marcel::Magic.canonical('alias/type')

    Marcel::Magic.remove('alias/type')
    assert_equal 'alias/type', Marcel::Magic.canonical('alias/type')
  end

  test "removing canonical removes aliases" do
    Marcel::Magic.add('canonical/type', aliases: %w[ alias/one alias/two ])
    assert_equal 'canonical/type', Marcel::Magic.canonical('alias/one')
    assert_equal 'canonical/type', Marcel::Magic.canonical('alias/two')

    Marcel::Magic.remove('canonical/type')
    assert_equal 'alias/one', Marcel::Magic.canonical('alias/one')
    assert_equal 'alias/two', Marcel::Magic.canonical('alias/two')
  end

  test "adding type removes existing alias" do
    Marcel::Magic.add('canonical/type', aliases: 'alias/type')
    assert_equal 'canonical/type', Marcel::Magic.canonical('alias/type')

    Marcel::Magic.add('alias/type', comment: "overrides old alias")
    assert_equal 'alias/type', Marcel::Magic.canonical('alias/type')
  end

  test "#extensions" do
    json = Marcel::Magic.by_extension('json')
    assert_equal ['json'], json.extensions
  end

  test ".child?" do
    assert Marcel::Magic.child?('text/csv', 'text/plain')
    refute Marcel::Magic.child?('text/plain', 'text/csv')
  end

  test "child? with aliases" do
    Marcel::Magic.add('canonical/parent', aliases: 'alias/parent')
    Marcel::Magic.add('canonical/child', aliases: 'alias/child', parents: 'canonical/parent')

    assert Marcel::Magic.child?('alias/child', 'alias/parent')
  end
end
