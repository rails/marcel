require 'test_helper'
require 'rack'

class Marcel::MimeType::MagicTest < Marcel::TestCase
  # These fixtures should be recognisable given only their contents. Where a generic type
  # has more specific subclasses (such as application/zip), these subclasses cannot usually
  # be recognised by magic alone; their name is also needed to correctly identify them.
  each_content_type_fixture('magic') do |file, name, content_type|
    test "gets type for #{content_type} by using only magic bytes #{name}" do
      actual_type = Marcel::MimeType.for(file)
      assert_equal content_type, actual_type, "Expected #{file} to be #{content_type}, but was #{actual_type}"
    end
  end

  test "add and remove type" do
    Marcel::Magic.add('application/x-my-thing', extensions: 'mtg', parents: 'application/json')
    Marcel::Magic.remove('application/x-my-thing')
  end

  test "switch canonical type" do
    Marcel::Magic.add('canonical/type', aliases: 'alias/type', extensions: %w[ canonical ], parents: 'canonical/parent', magic: [[0, 'magic']])
    assert Marcel::Magic.child?('canonical/type', 'canonical/parent')
    assert_equal 'canonical/type', Marcel::Magic.canonical('alias/type')
    assert_equal 'canonical/type', Marcel::Magic.by_extension('canonical').type
    assert_equal 'canonical/type', Marcel::Magic.by_magic('magic').type
    assert_equal %w[ canonical ], Marcel::Magic.new('canonical/type').extensions

    Marcel::Magic.canonicalize('alias/type', instead_of: 'canonical/type')
    assert Marcel::Magic.child?('alias/type', 'canonical/parent')
    assert_equal 'alias/type', Marcel::Magic.canonical('alias/type')
    assert_equal 'alias/type', Marcel::Magic.canonical('canonical/type')
    assert_equal 'alias/type', Marcel::Magic.by_extension('canonical').type
    assert_equal 'alias/type', Marcel::Magic.by_magic('magic').type
    assert_equal %w[ canonical ], Marcel::Magic.new('alias/type').extensions
  ensure
    Marcel::Magic.remove('alias/type')
    Marcel::Magic.remove('canonical/type')
  end

  test "canonicalizing instead of an alias is an error" do
    Marcel::Magic.add('canonical/type', aliases: 'alias/type')

    assert_raises ArgumentError do
      Marcel::Magic.canonicalize('other/type', instead_of: 'alias/type')
    end
  ensure
    Marcel::Magic.remove('canonical/type')
  end

  test "removing alias" do
    Marcel::Magic.add('canonical/type', aliases: 'alias/type')
    assert_equal 'canonical/type', Marcel::Magic.canonical('alias/type')

    Marcel::Magic.remove('alias/type')
    assert_equal 'alias/type', Marcel::Magic.canonical('alias/type')
  ensure
    Marcel::Magic.remove('canonical/type')
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
  ensure
    Marcel::Magic.remove('alias/type')
    Marcel::Magic.remove('canonical/type')
  end

  test "aliases are normalized to lowercase" do
    Marcel::Magic.add('canonical/type', aliases: 'Alias/Type')
    assert_equal 'canonical/type', Marcel::Magic.canonical('alias/type')
    assert_equal 'canonical/type', Marcel::Magic.canonical('Alias/Type')
  ensure
    Marcel::Magic.remove('canonical/type')
  end

  test "aliasing a registered type is an error and leaves every registry untouched" do
    Marcel::Magic.add('registered/type', extensions: 'reg')
    snapshots = [Marcel::EXTENSIONS, Marcel::TYPE_EXTS, Marcel::TYPE_PARENTS,
                 Marcel::TYPE_ALIASES, Marcel::MAGIC].map(&:dup)

    assert_raises ArgumentError do
      Marcel::Magic.add('candidate/type', extensions: 'txt', parents: 'text/plain',
        magic: [[0, 'candidate']], aliases: %w[ alias/fine registered/type ])
    end

    assert_equal snapshots,
      [Marcel::EXTENSIONS, Marcel::TYPE_EXTS, Marcel::TYPE_PARENTS, Marcel::TYPE_ALIASES, Marcel::MAGIC]
    assert_equal 'text/plain', Marcel::Magic.by_extension('txt').type
  ensure
    Marcel::Magic.remove('registered/type')
  end

  test "canonicalizing re-points existing aliases so resolution stays single-hop" do
    Marcel::Magic.add('first/type', aliases: 'alias/type')
    Marcel::Magic.canonicalize('second/type', instead_of: 'first/type')

    assert_equal 'second/type', Marcel::Magic.canonical('first/type')
    assert_equal 'second/type', Marcel::Magic.canonical('alias/type')
  ensure
    Marcel::Magic.remove('second/type')
    Marcel::Magic.remove('first/type')
  end

  test "#extensions" do
    json = Marcel::Magic.by_extension('json')
    assert_equal ['json'], json.extensions
  end

  test ".child?" do
    assert Marcel::Magic.child?('text/csv', 'text/plain')
    refute Marcel::Magic.child?('text/plain', 'text/csv')
  end

  test ".child? with aliases" do
    Marcel::Magic.add('canonical/parent', aliases: 'alias/parent')
    Marcel::Magic.add('canonical/child', aliases: 'alias/child', parents: 'canonical/parent')

    assert Marcel::Magic.child?('alias/child', 'alias/parent')
  ensure
    Marcel::Magic.remove('canonical/child')
    Marcel::Magic.remove('canonical/parent')
  end

  test "X bitmap resolves its C source alias to a canonical text parent" do
    assert Marcel::Magic.child?('image/x-xbitmap', 'text/x-csrc')
    assert Marcel::Magic.new('image/x-xbitmap').text?
  end

  test ".child? handles custom parent cycles" do
    Marcel::Magic.add('application/x-cycle-a', parents: 'application/x-cycle-b')
    Marcel::Magic.add('application/x-cycle-b', parents: 'application/x-cycle-a')

    refute Marcel::Magic.child?('application/x-cycle-a', 'application/zip')
  ensure
    Marcel::Magic.remove('application/x-cycle-a')
    Marcel::Magic.remove('application/x-cycle-b')
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

  test "none of the regex patterns should match random test data" do
    ignore_list = %w( application/x-dbf )

    extract_regexes = lambda do |matching_rules, collected = []|
      matching_rules.each do |offset, value, children|
        collected << [offset, value] if value.is_a?(Regexp)
        extract_regexes.call(children, collected) if children
      end
      collected
    end

    # Use a test string that's very unlikely to match any file format regex
    # Using only high Unicode characters and very specific patterns
    test_data = "🇨🇭 \xFF\xFE\x03\x05\x06🧀 cheese\x06\x07\x03"

    Marcel::MAGIC.each do |type, matching_rules|
      next if ignore_list.include?(type)
      regexes = extract_regexes.call(matching_rules)

      result = Marcel::Magic.send(:magic_match_io, StringIO.new(test_data), regexes, "".b)
      assert_equal false, result, "Test data unexpectedly matched a file format regexp (#{type}, #{regexes.inspect})"
    end
  end

  test "nested match: parent AND child must both match" do
    # Rule: offset 0 matches "AAA" AND offset 3 matches "BBB"
    # This should match "AAABBB" but not "AAA" alone
    test_rules = [
      [0, "AAA".b, [[3, "BBB".b]]]
    ]
    
    buffer = (+"").encode(Encoding::BINARY)
    
    # Should match when both parent and child match
    io1 = StringIO.new("AAABBB")
    assert Marcel::Magic.send(:magic_match_io, io1, test_rules, buffer),
           "Should match when parent and child both match"
    
    # Should NOT match when parent matches but child doesn't
    io2 = StringIO.new("AAAXXX")
    refute Marcel::Magic.send(:magic_match_io, io2, test_rules, buffer),
           "Should not match when parent matches but child doesn't"
  end

  test "sibling matches use OR logic" do
    # Two sibling rules: either can match
    # Rule 1: offset 0 matches "XXX"
    # Rule 2: offset 0 matches "YYY"
    test_rules = [
      [0, "XXX".b],
      [0, "YYY".b]
    ]
    
    buffer = (+"").encode(Encoding::BINARY)
    
    # Should match via first sibling
    io1 = StringIO.new("XXX")
    assert Marcel::Magic.send(:magic_match_io, io1, test_rules, buffer),
           "Should match via first sibling rule"
    
    # Should match via second sibling
    io2 = StringIO.new("YYY")
    assert Marcel::Magic.send(:magic_match_io, io2, test_rules, buffer),
           "Should match via second sibling rule"
    
    # Should NOT match when no sibling matches
    io3 = StringIO.new("ZZZ")
    refute Marcel::Magic.send(:magic_match_io, io3, test_rules, buffer),
           "Should not match when no sibling rule matches"
  end

  test "parent with multiple child alternatives (OR)" do
    # Test complex nested structure: parent AND (child1 OR child2)
    # Parent at offset 0 matches "ROOT"
    # Child option 1: offset 4 matches "OPT1"
    # Child option 2: offset 4 matches "OPT2"
    test_rules = [
      [0, "ROOT".b, [
        [4, "OPT1".b],  # First child option
        [4, "OPT2".b]   # Second child option (sibling OR)
      ]]
    ]
    
    buffer = (+"").encode(Encoding::BINARY)
    
    # Should match when parent and first child match
    io1 = StringIO.new("ROOTOPT1")
    assert Marcel::Magic.send(:magic_match_io, io1, test_rules, buffer),
           "Should match when parent and first child match"
    
    # Should match when parent and second child match
    io2 = StringIO.new("ROOTOPT2")
    assert Marcel::Magic.send(:magic_match_io, io2, test_rules, buffer),
           "Should match when parent and second child match"
    
    # Should NOT match when parent matches but no child matches
    io3 = StringIO.new("ROOTXXXX")
    refute Marcel::Magic.send(:magic_match_io, io3, test_rules, buffer),
           "Should not match when parent matches but no child matches"
  end

  test "negative offsets do not scan from the start of short data" do
    rules = [[-64, %r{\A<html>}]]

    refute Marcel::Magic.send(:magic_match_io, StringIO.new("<html>"), rules, "".b)
  end

  test "negative offsets are skipped when the IO has no size" do
    io = Class.new do
      def initialize(data)
        @io = StringIO.new(data)
      end

      def read(*args)
        @io.read(*args)
      end

      def seek(*args)
        @io.seek(*args)
      end

      def rewind
        @io.rewind
      end
    end.new("x" * 64 + "</html>")

    rules = [[-64, %r{</html>\z}]]

    refute Marcel::Magic.send(:magic_match_io, io, rules, "".b)
  end

  test "non-seekable IO consumes exact offsets despite short reads" do
    io = Class.new do
      def initialize(data)
        @io = StringIO.new(data)
        @first_read = true
      end

      def read(length)
        length = 1 if @first_read
        @first_read = false
        @io.read(length)
      end

      def rewind
        @first_read = true
        @io.rewind
      end
    end.new("Xftypavif")

    assert_equal "application/octet-stream", Marcel::MimeType.for(io)
  end

  test "two-argument non-seekable IO consumes exact offsets despite short reads" do
    io = Class.new do
      def initialize(data)
        @io = StringIO.new(data)
      end

      def read(length, buffer)
        chunk = @io.read([length, 1].min)
        chunk ? buffer.replace(chunk) : nil
      end

      def rewind
        @io.rewind
      end
    end.new("Xftypavif")

    assert_equal "application/octet-stream", Marcel::MimeType.for(io)
  end

  test "custom IO samples are matched as binary data" do
    one_argument_reader = Class.new do
      def initialize(data)
        @io = StringIO.new(data)
      end

      def read(length)
        @io.read(length)&.force_encoding(Encoding::UTF_8)
      end

      def rewind
        @io.rewind
      end
    end

    two_argument_reader = Class.new do
      def initialize(data)
        @io = StringIO.new(data)
      end

      def read(length, buffer)
        chunk = @io.read(length)
        chunk ? buffer.replace(chunk).force_encoding(Encoding::UTF_8) : nil
      end

      def rewind
        @io.rewind
      end
    end

    [one_argument_reader, two_argument_reader].each do |reader|
      assert_equal "text/html", Marcel::MimeType.for(reader.new("<html><body>café</body></html>"))
      assert_equal "image/png", Marcel::MimeType.for(reader.new(File.binread(files("magic/image/png/png.png"))))
    end
  end

  test "non-seekable IO skips offset rules at early EOF" do
    io = Class.new do
      def initialize(data)
        @io = StringIO.new(data)
      end

      def read(length)
        @io.read([length, 1].min)
      end

      def rewind
        @io.rewind
      end
    end.new("Xft")

    rules = [[4, "ftypavif".b]]

    refute Marcel::Magic.send(:magic_match_io, io, rules, "".b)
  end

  test "public magic matching rewinds after a read exception" do
    io = Class.new do
      def initialize
        @io = StringIO.new("data")
      end

      def read(*_args)
        @io.read(1)
        raise IOError, "read failed"
      end

      def rewind
        @io.rewind
      end

      def position
        @io.pos
      end
    end.new

    assert_raises(IOError) { Marcel::Magic.by_magic(io) }
    assert_equal 0, io.position
  end

  test "a cleanup rewind failure does not mask a read failure" do
    original_error = ArgumentError.new("original read failed")
    io = Class.new do
      def initialize(original_error)
        @original_error = original_error
        @rewinds = 0
      end

      def read(*)
        raise @original_error
      end

      def rewind
        @rewinds += 1
        raise IOError, "cleanup rewind failed" if @rewinds > 1
      end
    end.new(original_error)

    raised_error = assert_raises(ArgumentError) { Marcel::Magic.by_magic(io) }
    assert_same original_error, raised_error
  end

  test "a cleanup rewind failure is preserved after successful matching" do
    Marcel::Magic.add("application/x-cleanup-test", magic: [[0, "MATCH"]])
    io = Class.new do
      def initialize(data)
        @io = StringIO.new(data)
        @rewinds = 0
      end

      def read(*args)
        @io.read(*args)
      end

      def rewind
        @rewinds += 1
        raise IOError, "cleanup rewind failed" if @rewinds == 3

        @io.rewind
      end
    end.new("MATCH")

    error = assert_raises(IOError) { Marcel::Magic.by_magic(io) }
    assert_equal "cleanup rewind failed", error.message
  ensure
    Marcel::Magic.remove("application/x-cleanup-test")
  end

  test "public magic matching accepts Pathnames and closes their files" do
    path_class = Class.new(Pathname) do
      attr_reader :opened_files

      def initialize(path)
        super
        @opened_files = []
      end

      def open(*arguments)
        file = File.open(to_path, *arguments)
        @opened_files << file
        return file unless block_given?

        begin
          yield file
        ensure
          file.close
        end
      end
    end
    path = path_class.new(files("image.gif").to_s)

    assert_equal "image/gif", Marcel::Magic.by_magic(path).type
    assert_includes Marcel::Magic.all_by_magic(path).map(&:type), "image/gif"
    assert_equal 2, path.opened_files.size
    assert path.opened_files.all?(&:closed?)
  end

  test "complex nested structure with multiple levels" do
    # Parent AND (Child AND Grandchild)
    # offset 0: "AAA", offset 3: "BBB", offset 6: "CCC"
    test_rules = [
      [0, "AAA".b, [
        [3, "BBB".b, [
          [6, "CCC".b]
        ]]
      ]]
    ]
    
    buffer = (+"").encode(Encoding::BINARY)
    
    # Should match when all levels match
    io1 = StringIO.new("AAABBBCCC")
    assert Marcel::Magic.send(:magic_match_io, io1, test_rules, buffer),
           "Should match when all nested levels match"
    
    # Should NOT match when grandchild doesn't match
    io2 = StringIO.new("AAABBBXXX")
    refute Marcel::Magic.send(:magic_match_io, io2, test_rules, buffer),
           "Should not match when deepest child doesn't match"
  end
end
