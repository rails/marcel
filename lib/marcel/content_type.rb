require 'mimemagic'

class Marcel::ContentType
  BINARY = "application/octet-stream"

  class << self
    def for(io, name: nil, declared_type: nil)
      by_magic(io) || by_declared_type(declared_type) || by_name(name)  || BINARY
    end

    private
      def by_magic(io)
        io = coerce_to_io(io)
        MimeMagic.by_magic(io)&.type
      end

      def by_name(name)
        if name
          MimeMagic.by_path(name)&.type
        end
      end

      def by_declared_type(declared_type)
        type = parse_media_type(declared_type)

        if type != BINARY
          type
        end
      end

      def coerce_to_io(io)
        case io
        when Pathname
          io.open
        else
          io
        end
      end

      def parse_media_type(content_type)
        if content_type
          content_type.downcase.split(/[;,\s]/, 2).first.presence
        end
      end
  end
end
