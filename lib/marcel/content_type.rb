require 'marcel/definitions'

class Marcel::ContentType
  BINARY = "application/octet-stream"

  SUBTYPES = Hash.new([])
  SUBTYPES["application/vnd.openxmlformats-officedocument.wordprocessingml.document"] = %w(
    application/vnd.openxmlformats-officedocument.wordprocessingml.template
    application/vnd.ms-word.document.macroenabled.12
    application/vnd.ms-word.template.macroenabled.12
  )

  SUBTYPES["application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"] = %w(
    application/vnd.openxmlformats-officedocument.spreadsheetml.template
    application/vnd.ms-excel.sheet.macroenabled.12
    application/vnd.ms-excel.template.macroenabled.12
    application/vnd.ms-excel.addin.macroenabled.12
    application/vnd.ms-excel.sheet.binary.macroenabled.12
  )

  SUBTYPES["application/vnd.openxmlformats-officedocument.presentationml.presentation"] = %w(
    application/vnd.openxmlformats-officedocument.presentationml.template
    application/vnd.openxmlformats-officedocument.presentationml.slideshow
    application/vnd.ms-powerpoint.addin.macroenabled.12
    application/vnd.ms-powerpoint.presentation.macroenabled.12
    application/vnd.ms-powerpoint.template.macroenabled.12
    application/vnd.ms-powerpoint.slideshow.macroenabled.12
  )

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
      # type with magic, but not the specific subtype. In this situation, if we can get a more
      # specific type using either the name or declared_type, we should use that in preference
      def most_specific_type(from_magic_type, fallback_type)
        if fallback_type.in? SUBTYPES[from_magic_type]
          fallback_type
        else
          from_magic_type
        end
      end
  end
end
