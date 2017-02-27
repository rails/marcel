require 'marcel/mime_type/definitions'

class Marcel::MimeType
  autoload :Subclasses, 'marcel/mime_type/subclasses'

  BINARY = "application/octet-stream"

  class << self
    def for(io, name: nil, declared_type: nil)
      from_magic_type = by_magic(io)
      fallback_type = by_declared_type(declared_type) || by_name(name) || BINARY

      if from_magic_type
        most_specific_type from_magic_type, fallback_type
      else
        fallback_type
      end
    end

    def for_extension(extension)
      if extension
        MimeMagic.by_extension(extension)&.type&.downcase
      end
    end

    private
      def by_magic(io)
        io = coerce_to_io(io)
        MimeMagic.by_magic(io)&.type&.downcase
      end

      def by_name(name)
        if name
          MimeMagic.by_path(name)&.type&.downcase
        end
      end

      def by_declared_type(declared_type)
        type = parse_media_type(declared_type)

        if type != BINARY
          type&.downcase
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

      # For some document types (most notably Microsoft Office) we can recognise the main content
      # type with magic, but not the specific subclass. In this situation, if we can get a more
      # specific class using either the name or declared_type, we should use that in preference
      def most_specific_type(from_magic_type, fallback_type)
        if fallback_type.in? Subclasses.for(from_magic_type)
          fallback_type
        else
          from_magic_type
        end
      end
  end
end
