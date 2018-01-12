require 'test_helper'
require 'rack'

class Marcel::MimeTypeTest < Marcel::TestCase
  def setup
    @path = files("image.gif").to_s
  end

  test "gets content type from Files" do
    content_type = File.open @path do |file|
      Marcel::MimeType.for file
    end
    assert_equal "image/gif", content_type
  end

  test "gets content type from Pathnames" do
    content_type = Marcel::MimeType.for Pathname.new(@path)
    assert_equal "image/gif", content_type
  end

  test "closes Pathname files after use" do
    content_type = Marcel::MimeType.for Pathname.new(@path)
    open_files = ObjectSpace.each_object(File).reject(&:closed?)
    assert open_files.none? { |f| f.path == @path }
  end

  test "gets content type from Tempfiles" do
    Tempfile.open("Marcel") do |tempfile|
      tempfile.write(File.read(@path))
      content_type = Marcel::MimeType.for tempfile
      assert_equal "image/gif", content_type
    end
  end

  test "gets content type from IOs" do
    io = StringIO.new(File.read(@path))
    content_type = Marcel::MimeType.for io
    assert_equal "image/gif", content_type
  end

  test "gets content type from sources that conform to Rack::Lint::InputWrapper" do
    io = StringIO.new(File.read(@path))
    wrapper = Rack::Lint::InputWrapper.new(io)
    content_type = Marcel::MimeType.for wrapper
    assert_equal "image/gif", content_type
  end
end
