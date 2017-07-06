require 'active_support/all'
require 'minitest/autorun'
require 'marcel'

class ActiveSupport::TestCase
  class << self
    def fixture_path(name)
      File.expand_path("../fixtures/#{name}", __FILE__)
    end

    def files(name)
      Pathname.new fixture_path(name)
    end

    def each_content_type_fixture(folder)
      FileUtils.chdir fixture_path(folder) do
        Dir["**/*.*"].each.map do |name|
          if File.file?(name)
            _, content_type, extra, extension = *name.match(/\A([^\/]+\/[^\/]*)\/?(.*)\.(\w+)\Z/)
            extra = nil if content_type.ends_with?(extra)
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
