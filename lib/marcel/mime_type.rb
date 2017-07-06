class Marcel::MimeType
  BINARY = "application/octet-stream"

  class << self
    def add(type, extensions: [], parents: [], magic: nil)
      existing = MimeMagic::TYPES[type] || [[], [], ""]

      extensions = Array(extensions) + existing[0]
      parents = Array(parents) + existing[1]
      comment = existing[2]

      MimeMagic.add(type, extensions: extensions, magic: magic, parents: parents, comment: comment)
    end

    def for(io = nil, name: nil, extension: nil, declared_type: nil)
      type_from_data = for_data(io)
      fallback_type = for_declared_type(declared_type) || for_name(name) || for_extension(extension) || BINARY

      if type_from_data
        most_specific_type type_from_data, fallback_type
      else
        fallback_type
      end
    end

    private
      def for_data(io)
        if io
          io = coerce_to_io(io)
          MimeMagic.by_magic(io)&.type&.downcase
        end
      end

      def for_name(name)
        if name
          MimeMagic.by_path(name)&.type&.downcase
        end
      end

      def for_extension(extension)
        if extension
          MimeMagic.by_extension(extension)&.type&.downcase
        end
      end

      def for_declared_type(declared_type)
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

      # For some document types (notably Microsoft Office) we recognise the main content
      # type with magic, but not the specific subclass. In this situation, if we can get a more
      # specific class using either the name or declared_type, we should use that in preference
      def most_specific_type(from_magic_type, fallback_type)
        if MimeMagic.child?(fallback_type, from_magic_type)
          fallback_type
        else
          from_magic_type
        end
      end
  end
end

require 'marcel/mime_type/definitions'

