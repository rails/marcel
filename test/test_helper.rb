require 'minitest/autorun'
require 'marcel'

class Marcel::TestCase < MiniTest::Test
  class << self
    def setup(&block)
      define_method(:setup, &block)
    end

    def teardown(&block)
      define_method(:teardown, &block)
    end

    def test(name, &block)
      test_name = "test_#{name.gsub(/\s+/,'_')}".to_sym
      defined = instance_method(test_name) rescue false
      raise "#{test_name} is already defined in #{self}" if defined
      define_method(test_name, &block)
    end

    def fixture_path(name)
      File.expand_path("../fixtures/#{name}", __FILE__)
    end

    def files(name)
      Pathname.new fixture_path(name)
    end

    def each_content_type_fixture(folder)
      FileUtils.chdir fixture_path(folder) do
        Dir["**/*.*"].map do |name|
          if File.file?(name)
            _, content_type, extra, extension = *name.match(/\A([^\/]+\/[^\/]*)\/?(.*)\.(\w+)\Z/)
            extra = nil if content_type[-content_type.size..-1] == extra
            yield files("#{folder}/#{name}"), name, content_type
          end
        end
      end
    end
  end

  def files(name)
    Pathname.new fixture_path(name)
  end

  def fixture_path(name)
    self.class.fixture_path(name)
  end
end
