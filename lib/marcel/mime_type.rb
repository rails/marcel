# frozen_string_literal: true

module Marcel
  class MimeType
    BINARY = "application/octet-stream"
    MAX_DECLARED_TYPE_BYTES = 8 * 1024
    TOKEN = "[!#$%&'*+\\-.^_`|~0-9A-Za-z]+"
    QUOTED_STRING = '"(?:[\t\x20\x21\x23-\x5B\x5D-\x7E\x80-\xFF]|\\\\[\t\x20-\x7E\x80-\xFF])*"'
    MEDIA_TYPE = %r{\A(#{TOKEN}/#{TOKEN})(?:[ \t]*;[ \t]*#{TOKEN}=(?:#{TOKEN}|#{QUOTED_STRING}))*(?:[ \t]*;[ \t]*)?\z}n

    class << self
      def extend(type, extensions: [], parents: [], magic: nil)
        extensions = (Array(extensions) + Array(Marcel::TYPE_EXTS[type])).uniq
        parents = (Array(parents) + Array(Marcel::TYPE_PARENTS[type])).uniq
        Magic.add(type, extensions: extensions, magic: magic, parents: parents)
      end

      # Returns the most appropriate content type for the given file.
      #
      # The first argument should be a +Pathname+ or an +IO+. If it is a +Pathname+, the specified
      # file will be opened first.
      #
      # Optional parameters:
      # * +name+: file name, if known
      # * +extension+: file extension, if known
      # * +declared_type+: MIME type, if known
      #
      # The most appropriate type is determined by the following:
      # * type declared by binary magic number data
      # * valid declared MIME type, unless it is application/octet-stream
      # * type inferred from the file name or extension
      #
      # A later candidate is used only if it is more specific than the type already found.
      #
      # The result is a best-effort label, not validation that the file is safe or conforms to
      # the returned type. Treat +name+ and +declared_type+ as hints from their respective sources.
      #
      # If no type can be determined, then +application/octet-stream+ is returned.
      def for(pathname_or_io = nil, name: nil, extension: nil, declared_type: nil)
        filename_type = for_name(name) || for_extension(extension)
        most_specific_type for_data(pathname_or_io), for_declared_type(declared_type), filename_type, BINARY
      end

      private

        def for_data(pathname_or_io)
          if pathname_or_io
            with_io(pathname_or_io) do |io|
              if magic = Marcel::Magic.by_magic(io)
                Marcel::Magic::Zip.refine(io, magic.type.downcase)
              end
            end
          end
        end

        def for_name(name)
          if name
            if magic = Marcel::Magic.by_path(name)
              magic.type.downcase
            end
          end
        end

        def for_extension(extension)
          if extension
            if magic = Marcel::Magic.by_extension(extension)
              magic.type.downcase
            end
          end
        end

        def for_declared_type(declared_type)
          type = parse_media_type(declared_type)

          # application/octet-stream is treated as an undeclared/missing type,
          # allowing the type to be inferred from the filename. If there's no
          # filename extension, then the type falls back to binary anyway.
          type unless type == BINARY
        end

        def with_io(pathname_or_io, &block)
          if defined?(Pathname) && pathname_or_io.is_a?(Pathname)
            pathname_or_io.open("rb", &block)
          else
            yield pathname_or_io
          end
        end

        def parse_media_type(content_type)
          return unless content_type
          return if content_type.bytesize > MAX_DECLARED_TYPE_BYTES

          content_type = content_type.dup.force_encoding(Encoding::BINARY)
          content_type.sub!(/\A[ \t\r\n]+/n, "")
          content_type.sub!(/[ \t\r\n]+\z/n, "")

          media_type = MEDIA_TYPE.match(content_type)
          media_type[1].downcase.force_encoding(Encoding::UTF_8) if media_type
        end

        # For some document types (notably Microsoft Office) we recognise the main content
        # type with magic, but not the specific subclass. In this situation, if we can get a more
        # specific class using either the name or declared_type, we should use that in preference
        def most_specific_type(*candidates)
          candidates.compact.uniq.reduce do |type, candidate|
            Marcel::Magic.child?(candidate, type) ? candidate : type
          end
        end
    end
  end
end

require 'marcel/mime_type/definitions'
