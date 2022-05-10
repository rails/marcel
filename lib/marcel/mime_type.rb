# frozen_string_literal: true

module Marcel
  class MimeType
    BINARY = "application/octet-stream"

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
      # * type declared by the first of file name, file extension, or declared MIME type
      #
      # If no type can be determined, then +application/octet-stream+ is returned.
      def for(pathname_or_io = nil, name: nil, extension: nil, declared_type: nil)
        type_from_data = for_data(pathname_or_io)
        fallback_type = for_declared_type(declared_type) || for_name(name) || for_extension(extension) || BINARY

        if type_from_data
          most_specific_type type_from_data, fallback_type
        else
          fallback_type
        end
      end

      private

        def for_data(pathname_or_io)
          if pathname_or_io
            with_io(pathname_or_io) do |io|
              if magic = Marcel::Magic.by_magic(io)
                magic.type.downcase
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

          if type != BINARY && !type.nil?
            type.downcase
          end
        end

        def with_io(pathname_or_io, &block)
          if defined?(Pathname) && pathname_or_io.is_a?(Pathname)
            pathname_or_io.open(&block)
          else
            yield pathname_or_io
          end
        end

        def parse_media_type(content_type)
          if content_type
            result = content_type.downcase.split(/[;,\s]/, 2).first
            result if result && result.index("/")
          end
        end

        # For some document types (notably Microsoft Office) we recognise the main content
        # type with magic, but not the specific subclass. In this situation, if we can get a more
        # specific class using either the name or declared_type, we should use that in preference
        def most_specific_type(from_magic_type, fallback_type)
          if (root_types(from_magic_type) & root_types(fallback_type)).any?
            fallback_type
          else
            from_magic_type
          end
        end

        def root_types(type)
          if TYPE_EXTS[type].nil? || TYPE_PARENTS[type].nil?
            [ type ]
          else
            TYPE_PARENTS[type].map {|t| root_types t }.flatten
          end
        end
    end
  end
end

require 'marcel/mime_type/definitions'
