# frozen_string_literal: true

# Code in this file adapted from the mimemagic gem, released under the MIT License.
# Copyright (c) 2011 Daniel Mendler. Available at https://github.com/mimemagicrb/mimemagic.

require 'marcel/tables'

require 'stringio'

module Marcel
  # Mime type detection
  class Magic
    attr_reader :type, :mediatype, :subtype

    # Mime type by type string
    def initialize(type)
      @type = type
      @mediatype, @subtype = type.split('/', 2)
    end

    # Add custom mime type. Arguments:
    # * <i>type</i>: Mime type
    # * <i>options</i>: Options hash
    #
    # Option keys:
    # * <i>:extensions</i>: String list or single string of file extensions
    # * <i>:parents</i>: String list or single string of parent mime types
    # * <i>:aliases</i>: String list or single string of aliased mime types
    # * <i>:magic</i>: Mime magic specification
    # * <i>:comment</i>: Comment string
    def self.add(type, options)
      # Validate the complete registration before mutating any table, so a rejected
      # registration leaves every registry untouched.
      #
      # Alias keys are never registered types and alias values never alias keys, so
      # resolution is single-hop by construction: aliasing a registered type is rejected
      # here, and canonicalize (the sanctioned path) re-points existing aliases itself.
      aliases = [options[:aliases]].flatten.compact.map(&:downcase) - [type.downcase]
      aliases.each do |aliased|
        if TYPE_EXTS.key?(aliased) || TYPE_PARENTS.key?(aliased) || MAGIC.any? { |t, _| t == aliased }
          raise ArgumentError, "#{aliased} is a registered type; use canonicalize to alias it to #{type}"
        end
      end

      extensions = [options[:extensions]].flatten.compact
      TYPE_EXTS[type] = extensions
      extensions.each {|ext| EXTENSIONS[ext] = type }

      TYPE_ALIASES.delete(type)
      aliases.each {|aliased| TYPE_ALIASES[aliased] = type }

      parents = [options[:parents]].flatten.compact
      TYPE_PARENTS[type] = parents unless parents.empty?

      MAGIC.unshift [type, options[:magic]] if options[:magic]
    end

    # Renames a canonical type: the +instead_of+ type's extensions, magic matchers, parents,
    # and aliases are re-registered under +type+, and the old name becomes an alias of the
    # new. Useful when a historical or de facto type is preferable to the canonical type
    # shipped in the generated tables, without giving up its matchers.
    def self.canonicalize(type, instead_of:)
      raise ArgumentError, "#{instead_of} is an alias, not canonical" if TYPE_ALIASES[instead_of]

      # Displace whatever the new canonical type was registered as before.
      remove(type)

      # Re-register the old canonical type's dictionary under the new name.
      EXTENSIONS.select { |_, existing| existing == instead_of }.each_key do |ext|
        EXTENSIONS[ext] = type
      end

      if extensions = TYPE_EXTS.delete(instead_of)
        TYPE_EXTS[type] = extensions
      end

      TYPE_ALIASES.select { |_, canonical| canonical == instead_of }.each_key do |aliased|
        TYPE_ALIASES[aliased] = type
      end

      if parents = TYPE_PARENTS.delete(instead_of)
        TYPE_PARENTS[type] = parents
      end

      MAGIC.each { |pair| pair[0] = type if pair[0] == instead_of }

      # Alias the old canonical type to the new.
      TYPE_ALIASES[instead_of] = type
    end

    # Removes a mime type from the dictionary. You might want to do this if
    # you're seeing impossible conflicts (for instance, application/x-gmc-link).
    # * <i>type</i>: The mime type to remove. All associated extensions, magic,
    #   and aliases are removed too.
    def self.remove(type)
      EXTENSIONS.delete_if {|ext, t| t == type }
      MAGIC.delete_if {|t, m| t == type }
      TYPE_EXTS.delete(type)
      TYPE_PARENTS.delete(type)
      TYPE_ALIASES.delete_if {|aliased, canonical| aliased == type || canonical == type }
    end

    # Returns true if type is a text format
    def text?; mediatype == 'text' || child_of?('text/plain'); end

    # Mediatype shortcuts
    def image?; mediatype == 'image'; end
    def audio?; mediatype == 'audio'; end
    def video?; mediatype == 'video'; end

    # Returns true if type is child of parent type
    def child_of?(parent)
      self.class.child?(type, parent)
    end

    # Get string list of file extensions
    def extensions
      TYPE_EXTS[type] || []
    end

    # Resolve an aliased type to its canonical type; canonical types return themselves
    def canonical
      if canonical_type = TYPE_ALIASES[type]
        self.class.new(canonical_type)
      else
        self
      end
    end

    # Get mime comment
    def comment
      nil # deprecated
    end

    # Lookup canonical mime type by mime type string, resolving aliases
    def self.by_type(type)
      new(canonical(type)) if type
    end

    # Lookup mime type by file extension
    def self.by_extension(ext)
      ext = ext.to_s
      return unless ext.valid_encoding?

      ext = ext.downcase
      mime = ext[0..0] == '.' ? EXTENSIONS[ext[1..-1]] : EXTENSIONS[ext]
      mime && new(mime)
    end

    # Lookup mime type by filename
    def self.by_path(path)
      by_extension(File.extname(path))
    rescue ArgumentError, EncodingError
      nil
    end

    # Lookup mime type by magic content analysis.
    # This is a slow operation.
    def self.by_magic(io)
      mime = magic_match(io, :find)
      mime && new(mime[0])
    end

    # Lookup all mime types by magic content analysis.
    # This is a slower operation.
    def self.all_by_magic(io)
      magic_match(io, :select).map { |mime| new(mime[0]) }
    end

    # Return type as string
    def to_s
      type
    end

    # Allow comparison with string
    def eql?(other)
      type == other.to_s
    end

    def hash
      type.hash
    end

    alias == eql?

    def self.child?(child, parent)
      parent = canonical(parent)
      pending = [child]
      visited = {}

      until pending.empty?
        type = canonical(pending.pop)
        return true if type == parent
        next if visited[type]

        visited[type] = true
        pending.concat(TYPE_PARENTS[type] || [])
      end

      false
    end

    # Resolve an aliased type string to its canonical type string
    def self.canonical(type)
      if type
        # Allocation-free for already-lowercase input: child? resolves every node it visits.
        type = type.downcase if /[A-Z]/.match?(type)
        TYPE_ALIASES[type] || type
      end
    end

    def self.magic_match(io, method)
      if defined?(Pathname) && io.is_a?(Pathname)
        return io.open("rb") { |file| magic_match(file, method) }
      end

      return magic_match(StringIO.new(io.to_s), method) unless io.respond_to?(:read)

      buffer = "".b
      read_mode = read_mode(io)
      io.rewind
      body_failed = true
      begin
        result = MAGIC.send(method) { |type, matches| magic_match_io(io, matches, buffer, read_mode) }
        body_failed = false
        result
      ensure
        begin
          io.rewind
        rescue Exception # Preserve an exception already raised while reading or matching.
          raise unless body_failed
        end
      end
    end

    def self.magic_match_io(io, matches, buffer, mode = read_mode(io))
      matches.any? do |offset, value, children|
        match = if value
          is_range = Range === offset
          is_regexp = Regexp === value
          sample_size = is_regexp ? 256 : value.bytesize

          x = if is_range
            if io_seek(io, offset.begin, buffer, mode)
              io_read(io, offset.end - offset.begin + sample_size, buffer, mode)
            end
          else
            if io_seek(io, offset, buffer, mode)
              io_read(io, sample_size, buffer, mode)
            end
          end
          x.force_encoding(Encoding::BINARY) if x

          if is_regexp
            x&.match?(value)
          elsif is_range
            x&.include?(value)
          else
            x == value
          end
        end

        io.rewind
        match && (!children || magic_match_io(io, children, buffer, mode))
      end
    end

    def self.io_seek(io, offset, buffer, mode)
      return true if offset == 0

      if offset < 0
        return false unless io.respond_to?(:size)

        offset = io.size + offset
        return false if offset < 0
      end

      if io.respond_to?(:seek)
        io.seek(offset, IO::SEEK_SET)
      else
        # Some IOs don't support `seek`. e.g. Rack::RewindableInput
        skipped = io_read(io, offset, buffer, mode)
        return false unless skipped && skipped.bytesize == offset
      end

      true
    end

    def self.io_read(io, length, buffer, mode)
      return io.read(length, buffer) if mode == :native

      buffer.clear

      read_with_buffer = mode == :buffer
      chunk = read_with_buffer ? io.read(length, buffer) : io.read(length)
      return if chunk && chunk.bytesize > length
      buffer.replace(chunk) if chunk && !chunk.equal?(buffer)

      return if chunk.nil? || buffer.empty?
      return buffer if buffer.bytesize == length

      continuation_buffer = "".b if read_with_buffer
      while buffer.bytesize < length
        remaining = length - buffer.bytesize
        chunk = if read_with_buffer
          io.read(remaining, continuation_buffer.clear)
        else
          io.read(remaining)
        end
        return if chunk && chunk.bytesize > remaining
        break if chunk.nil? || chunk.empty?

        buffer << chunk
      end

      buffer unless buffer.empty?
    end

    def self.read_mode(io)
      return :native if io.is_a?(IO) || io.is_a?(StringIO)

      parameters = io.method(:read).parameters
      supports_buffer = parameters.any? { |kind,| kind == :rest } ||
        parameters.count { |kind,| kind == :req || kind == :opt } >= 2
      supports_buffer ? :buffer : :single
    end

    private_class_method :magic_match, :magic_match_io, :io_seek, :io_read, :read_mode
  end
end

require "marcel/magic/definitions"
require "marcel/magic/xml"
require "marcel/magic/zip"
