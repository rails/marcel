require 'test_helper'
require 'rack'

class Marcel::ContentTypeTest < ActiveSupport::TestCase
  setup do
    @path = files("image.gif").to_s
  end

  test "gets content type from Files" do
    content_type = Marcel::ContentType.for File.new(@path)
    assert_equal "image/gif", content_type
  end

  test "gets content type from Pathnames" do
    content_type = Marcel::ContentType.for Pathname.new(@path)
    assert_equal "image/gif", content_type
  end

  test "gets content type from Tempfiles" do
    Tempfile.open do |tempfile|
      tempfile.write(File.read(@path))
      content_type = Marcel::ContentType.for tempfile
      assert_equal "image/gif", content_type
    end
  end

  test "gets content type from IOs" do
    io = StringIO.new(File.read(@path))
    content_type = Marcel::ContentType.for io
    assert_equal "image/gif", content_type
  end

  test "gets content type from sources that conform to Rack::Lint::InputWrapper" do
    io = StringIO.new(File.read(@path))
    wrapper = Rack::Lint::InputWrapper.new(io)
    content_type = Marcel::ContentType.for wrapper
    assert_equal "image/gif", content_type
  end
end
