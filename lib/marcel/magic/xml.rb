# frozen_string_literal: true

module Marcel
  class Magic
    # Procedural refinement of XML documents by their root element.
    #
    # Many XML vocabularies — feeds, KML, property lists, XSLT, Office 2003 XML — share the
    # same leading bytes, and a prolog of arbitrary length (declaration, comments, DOCTYPE)
    # can precede the element that tells them apart. Apache Tika identifies them by the root
    # element's namespace and local name instead, and those rules are generated into
    # ROOT_XML. This module scans a bounded prefix past the prolog to the root start-tag,
    # resolves the root's namespace from its own xmlns declarations, and looks the pair up
    # to refine a generic application/xml match.
    #
    # Tika hands the prefix to a namespace-aware SAX parser and takes no root when parsing
    # fails before the first start element, so the scan holds the same line at the token
    # level. The bytes consumed up to the end of the root start-tag must be valid in the
    # document's encoding and free of characters the XML version forbids as literals. The
    # XML declaration may appear only first, parsed in full and limited to versions 1.0 and
    # 1.1; no other processing instruction may use the reserved xml target, and a PI's data
    # must be separated from its target by whitespace; comments may not contain "--". Names
    # — the root and attribute QNames, namespace prefixes, PI targets and reference names —
    # are validated as Unicode NCNames. Attribute values may not contain "<"; their
    # character references must denote characters the XML version admits, and their entity
    # references must be predefined unless a DTD that could declare them was seen.
    # References are validated, never resolved; nothing beyond the tokens is — no entities,
    # no DTD declarations, no external resources — and anything the scanner cannot read
    # with certainty leaves the generic type in place.
    module Xml
      REFINABLE_TYPE = "application/xml"

      # Tika examines at most this much of a document for its root element.
      MAX_SCAN = 64 * 1024

      UTF8_BOM = "\xEF\xBB\xBF".b
      UTF16LE_BOM = "\xFF\xFE".b
      UTF16BE_BOM = "\xFE\xFF".b

      # Byte-level scanner pattern for names: XML Name restricted to ASCII plus any
      # non-ASCII byte. It only locates tokens; every captured name is then validated
      # against the real Unicode name grammar (NCNAME below) after decoding.
      NAME = '[A-Za-z_:\x80-\xFF][A-Za-z0-9._:\-\x80-\xFF]*'
      SPACE = '[ \t\r\n]'
      ENCODING_NAME = '[A-Za-z][A-Za-z0-9._\-]*'

      WHITESPACE = /\G#{SPACE}*/n
      START_TAG = /\G<(#{NAME})/n
      ATTRIBUTE = /\G#{SPACE}+(#{NAME})#{SPACE}*=#{SPACE}*(?:"([^"<]*)"|'([^'<]*)')/n
      START_TAG_END = /\G#{SPACE}*\/?>/n
      PROCESSING_INSTRUCTION = /\G<\?(#{NAME})/n
      RESERVED_TARGET = /\A[Xx][Mm][Ll]\z/n

      # The complete declaration grammar: a SAX-supported version, then optionally encoding,
      # then optionally standalone, in that order, with nothing else before ?>. Matched in
      # full so that trailing or duplicated tokens cannot hide behind the PI skipper.
      XML_DECLARATION = /
        \A<\?xml
        #{SPACE}+version#{SPACE}*=#{SPACE}*(?:"(?<version>1\.[01])"|'(?<version>1\.[01])')
        (?:#{SPACE}+encoding#{SPACE}*=#{SPACE}*(?:"(?<encoding>#{ENCODING_NAME})"|'(?<encoding>#{ENCODING_NAME})'))?
        (?:#{SPACE}+standalone#{SPACE}*=#{SPACE}*(?:"(?:yes|no)"|'(?:yes|no)'))?
        #{SPACE}*\?>
      /xn

      # Entity and character references; anything else after & in an attribute value is a
      # well-formedness error. The digit bounds cover every code point through U+10FFFF.
      REFERENCE = /&(?:(?<name>#{NAME})|\#(?<decimal>[0-9]{1,7})|\#x(?<hex>[0-9A-Fa-f]{1,6}));/n

      # The five entities every XML document predefines; any other entity reference is only
      # potentially declared when the document carries a DTD.
      PREDEFINED_ENTITIES = %w( amp lt gt apos quot ).freeze

      # NCName under the XML 1.0 (5th ed.) Unicode name grammar: NameStartChar and
      # NameChar with the colon excluded, matched against decoded UTF-8 names.
      NCNAME = /\A[A-Z_a-z\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u02FF\u0370-\u037D\u037F-\u1FFF\u200C-\u200D\u2070-\u218F\u2C00-\u2FEF\u3001-\uD7FF\uF900-\uFDCF\uFDF0-\uFFFD\u{10000}-\u{EFFFF}][A-Z_a-z\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u02FF\u0370-\u037D\u037F-\u1FFF\u200C-\u200D\u2070-\u218F\u2C00-\u2FEF\u3001-\uD7FF\uF900-\uFDCF\uFDF0-\uFFFD\u{10000}-\u{EFFFF}\-.0-9\u00B7\u0300-\u036F\u203F-\u2040]*\z/

      # Characters each XML version forbids as literals, matched against the decoded
      # UTF-8 text. XML 1.1 restricts the C0 and C1 controls (NEL excepted) to character
      # references, where XML 1.0 forbids C0 outright but admits C1 literals.
      FORBIDDEN_CHARS = {
        "1.0" => /[\x00-\x08\x0B\x0C\x0E-\x1F\uFFFE\uFFFF]/,
        "1.1" => /[\x00-\x08\x0B\x0C\x0E-\x1F\u007F-\u0084\u0086-\u009F\uFFFE\uFFFF]/,
      }.freeze

      XML_NAMESPACE = "http://www.w3.org/XML/1998/namespace"
      XMLNS_NAMESPACE = "http://www.w3.org/2000/xmlns/"

      PROCESSING_INSTRUCTION_OPEN = "<?".b
      PROCESSING_INSTRUCTION_CLOSE = "?>".b
      COMMENT_OPEN = "<!--".b
      COMMENT_CLOSE = "-->".b
      DOUBLE_HYPHEN = "--".b
      DOCTYPE_OPEN = "<!DOCTYPE".b
      DOCTYPE_DELIMITER = /["'\[\]<>]/n
      SPACE_BYTES = [0x20, 0x09, 0x0D, 0x0A].freeze

      # Ruby resolves these to a process default rather than to a charset.
      PSEUDO_ENCODING_NAMES = %w( locale external filesystem ).freeze

      class << self
        # Returns the type ROOT_XML assigns to the IO's root element if +base_type+ is the
        # generic XML type and the root element can be read, or +base_type+ unchanged.
        # Partial reads, roots past MAX_SCAN, malformed or mis-encoded prologs, namespace
        # errors and unknown roots refine nothing: the base type stands.
        def refine(io, base_type)
          return base_type unless base_type == REFINABLE_TYPE

          io = StringIO.new(io.to_s) unless io.respond_to?(:read)

          root = begin
            if decoded = decode(read_prefix(io))
              root_element(*decoded)
            end
          rescue StandardError
            nil
          ensure
            begin
              io.rewind
            rescue StandardError
              nil
            end
          end

          type = root && ROOT_XML[root]
          type ? Magic.canonical(type) : base_type
        end

        private

          def read_prefix(io)
            io.rewind
            prefix = "".b
            while prefix.bytesize < MAX_SCAN && (chunk = io.read(MAX_SCAN - prefix.bytesize))
              break if chunk.empty?
              prefix << chunk.b
            end
            prefix.byteslice(0, MAX_SCAN)
          end

          # Returns [bytes to scan, encoding to validate them against, XML version], or nil
          # when the prefix cannot be decoded. The magic gate guarantees a byte order mark on
          # UTF-16 input, which is transcoded strictly to UTF-8 up front; other documents are
          # scanned as bytes and validated against their declared encoding, UTF-8 by default.
          def decode(prefix)
            if prefix.start_with?(UTF16LE_BOM)
              data = transcode(prefix.byteslice(2..), Encoding::UTF_16LE)
              if declaration = xml_declaration(data)
                [data, Encoding::UTF_8, declaration[0]]
              end
            elsif prefix.start_with?(UTF16BE_BOM)
              data = transcode(prefix.byteslice(2..), Encoding::UTF_16BE)
              if declaration = xml_declaration(data)
                [data, Encoding::UTF_8, declaration[0]]
              end
            else
              data = prefix.start_with?(UTF8_BOM) ? prefix.byteslice(3..) : prefix
              if declaration = xml_declaration(data)
                version, name = declaration
                encoding = name ? find_encoding(name) : Encoding::UTF_8
                [data, encoding, version] if encoding
              end
            end
          end

          # A code unit or surrogate pair split by the scan limit is the one sequence that
          # may legitimately be incomplete: it is dropped, since it lies beyond the scan.
          # Any other invalid sequence raises and refines nothing.
          def transcode(bytes, encoding)
            bytes = bytes.byteslice(0, bytes.bytesize & ~1).force_encoding(encoding)
            begin
              bytes.encode(Encoding::UTF_8).b
            rescue EncodingError
              bytes.byteslice(0, bytes.bytesize - 2).encode(Encoding::UTF_8).b
            end
          end

          # Returns [version, declared encoding name or nil] when the document either has no
          # XML declaration (version defaults to 1.0) or opens with one that is well-formed
          # in full, and nil when it opens with a malformed declaration or a processing
          # instruction that misuses the xml target.
          def xml_declaration(data)
            return ["1.0", nil] unless data.start_with?(PROCESSING_INSTRUCTION_OPEN)
            return nil unless target = PROCESSING_INSTRUCTION.match(data, 0)
            return ["1.0", nil] unless target[1].match?(RESERVED_TARGET)

            if declaration = XML_DECLARATION.match(data)
              [declaration[:version], declaration[:encoding]]
            end
          end

          def find_encoding(name)
            return nil if PSEUDO_ENCODING_NAMES.include?(name.downcase)

            encoding = Encoding.find(name)
            encoding if encoding.ascii_compatible? && !encoding.dummy? && encoding != Encoding::BINARY
          rescue ArgumentError
            nil
          end

          # Skips the prolog — whitespace, processing instructions (including the XML
          # declaration), comments and the document type declaration — and returns the
          # root element's [namespace, local name], or nil if no root start-tag is found.
          def root_element(data, encoding, version)
            pos = 0
            doctype_seen = false
            while pos
              pos = WHITESPACE.match(data, pos).end(0)

              if data.byteslice(pos, 2) == PROCESSING_INSTRUCTION_OPEN
                pos = skip_processing_instruction(data, pos, encoding)
              elsif data.byteslice(pos, 4) == COMMENT_OPEN
                pos = skip_comment(data, pos)
              elsif data.byteslice(pos, 9) == DOCTYPE_OPEN
                doctype_seen = true
                pos = skip_doctype(data, pos + 9, encoding)
              else
                return parse_start_tag(data, pos, encoding, version, doctype_seen)
              end
            end
          end

          # The XML declaration is the one processing instruction allowed the xml target,
          # and only as the very first bytes of the document (checked by xml_declaration).
          # A PI's data, when present, must be separated from its target by whitespace.
          def skip_processing_instruction(data, pos, encoding)
            return nil unless target = PROCESSING_INSTRUCTION.match(data, pos)
            return nil if pos != 0 && target[1].match?(RESERVED_TARGET)
            return nil unless pos == 0 && target[1].match?(RESERVED_TARGET) || valid_name?(target[1], encoding)

            after = target.end(0)
            return nil unless data.byteslice(after, 2) == PROCESSING_INSTRUCTION_CLOSE ||
              SPACE_BYTES.include?(data.getbyte(after))

            skip_past(data, PROCESSING_INSTRUCTION_CLOSE, after)
          end

          # A comment ends at its first "--", which must be the one closing it.
          def skip_comment(data, pos)
            close = data.index(DOUBLE_HYPHEN, pos + 4)
            close + 3 if close && data.byteslice(close, 3) == COMMENT_CLOSE
          end

          def skip_past(data, terminator, pos)
            close = data.index(terminator, pos)
            close + terminator.bytesize if close
          end

          # Advances past a document type declaration, honouring quoted literals and the
          # bracketed internal subset so that markup declarations like
          # <!ENTITY x "<foo>"> and comments within the subset cannot end the scan early.
          def skip_doctype(data, pos, encoding)
            depth = 0
            while pos && (pos = data.index(DOCTYPE_DELIMITER, pos))
              case data.getbyte(pos)
              when 0x22, 0x27 # " '
                pos = skip_past(data, data.byteslice(pos, 1), pos + 1)
              when 0x5B # [
                depth += 1
                pos += 1
              when 0x5D # ]
                depth -= 1
                pos += 1
              when 0x3C # <
                if data.byteslice(pos, 4) == COMMENT_OPEN
                  pos = skip_comment(data, pos)
                elsif data.byteslice(pos, 2) == PROCESSING_INSTRUCTION_OPEN
                  pos = skip_processing_instruction(data, pos, encoding)
                else
                  pos += 1
                end
              else # >
                return pos + 1 if depth <= 0
                pos += 1
              end
            end
          end

          # Reads the root start-tag's qualified name and attributes. Attribute values are
          # parsed as quoted literals so a > within one cannot truncate the tag; the tag must
          # close within the scanned prefix, and everything consumed up to that point must be
          # valid in the document's encoding and free of forbidden characters.
          def parse_start_tag(data, pos, encoding, version, doctype_seen)
            return nil unless tag = START_TAG.match(data, pos)

            qualified_name = tag[1]
            pos = tag.end(0)

            attributes = {}
            while attribute = ATTRIBUTE.match(data, pos)
              # Duplicate attributes are a well-formedness error (Unique Att Spec).
              return nil if attributes.key?(attribute[1])

              attributes[attribute[1]] = attribute[2] || attribute[3]
              pos = attribute.end(0)
            end
            return nil unless tag_end = START_TAG_END.match(data, pos)
            return nil unless valid_text?(data.byteslice(0, tag_end.end(0)), encoding, version)

            bindings = namespace_bindings(attributes, version)
            return nil unless bindings
            return nil unless valid_attributes?(attributes, bindings, encoding, version, doctype_seen)

            resolve_name(qualified_name, bindings, encoding)
          end

          # The consumed prefix must be valid in the document's encoding and free of the
          # characters its XML version forbids as literals, wherever they fall — comment,
          # PI, DOCTYPE or attribute — since a SAX parser rejects them before the root.
          def valid_text?(consumed, encoding, version)
            consumed = consumed.force_encoding(encoding)
            consumed.valid_encoding? &&
              !consumed.encode(Encoding::UTF_8).match?(FORBIDDEN_CHARS.fetch(version))
          end

          # Names — QName parts, prefixes, PI targets and entity names — must be NCNames
          # under the Unicode name grammar once decoded; the byte-level scanner accepts a
          # superset purely to locate them. Namespaces well-formedness leaves no room for
          # colons in any of these, so NCName is the grammar throughout.
          def valid_name?(name, encoding)
            NCNAME.match?(name.dup.force_encoding(encoding).encode(Encoding::UTF_8))
          rescue EncodingError
            false
          end

          # A character reference must denote a character the XML version admits: never a
          # surrogate, a noncharacter, or a code point beyond U+10FFFF; XML 1.0 admits only
          # tab, newline, carriage return and #x20 up, while XML 1.1 admits everything from
          # #x1 — including as references the control characters it forbids as literals.
          def valid_character_scalar?(value, version)
            return false if value > 0x10FFFF || value.between?(0xD800, 0xDFFF) ||
              value == 0xFFFE || value == 0xFFFF

            if version == "1.1"
              value >= 0x1
            else
              value == 0x9 || value == 0xA || value == 0xD || value >= 0x20
            end
          end

          # Every & in an attribute value must begin a well-formed reference: a character
          # reference to an admissible character, a predefined entity, or — only when a DTD
          # that could declare it was seen — any well-named entity. Never resolved.
          def valid_references?(value, encoding, version, doctype_seen)
            well_formed = true
            rest = value.gsub(REFERENCE) do
              reference = Regexp.last_match
              well_formed &&= if scalar = reference[:decimal] || reference[:hex]
                valid_character_scalar?(reference[:decimal] ? scalar.to_i : scalar.to_i(16), version)
              else
                valid_name?(reference[:name], encoding) &&
                  (doctype_seen || PREDEFINED_ENTITIES.include?(reference[:name]))
              end
              ""
            end
            well_formed && !rest.include?("&")
          end

          # Splits a QName into [prefix or nil, local name]; more than one colon or an empty
          # part is a namespace error, returned as nil.
          def split_qualified_name(name)
            if name.include?(":")
              prefix, local_name = name.split(":", 2)
              [prefix, local_name] unless prefix.empty? || local_name.empty? || local_name.include?(":")
            else
              [nil, name]
            end
          end

          # The tag's namespace declarations as {prefix or nil => namespace or nil}, with
          # the xml prefix implicitly bound. The xml and xmlns names and namespaces are
          # reserved. A prefix bound to an empty namespace is an undeclaration, permitted by
          # Namespaces 1.1 (except for xml) and an error under 1.0; violations are namespace
          # errors, returned as nil.
          def namespace_bindings(attributes, version)
            bindings = { nil => nil, "xml" => XML_NAMESPACE }
            attributes.each do |name, value|
              if name == "xmlns"
                return nil if value == XML_NAMESPACE || value == XMLNS_NAMESPACE
                bindings[nil] = value.empty? ? nil : value
              elsif name.start_with?("xmlns:")
                prefix = name.byteslice(6..)
                return nil if prefix.empty? || prefix.include?(":") || prefix == "xmlns"

                if value.empty?
                  return nil unless version == "1.1" && prefix != "xml"

                  bindings.delete(prefix)
                else
                  return nil if (prefix == "xml") != (value == XML_NAMESPACE)
                  return nil if value == XMLNS_NAMESPACE

                  bindings[prefix] = value
                end
              end
            end
            bindings
          end

          # Ordinary attributes resolved by expanded name, as a namespace-aware parser sees
          # them: names must be valid NCNames, prefixes bound, [namespace, local name] pairs
          # unique (the default namespace does not apply to attributes), and values free of
          # malformed references.
          def valid_attributes?(attributes, bindings, encoding, version, doctype_seen)
            expanded = {}
            attributes.each do |name, value|
              return false unless valid_references?(value, encoding, version, doctype_seen)

              if name == "xmlns"
                next
              elsif name.start_with?("xmlns:")
                return false unless valid_name?(name.byteslice(6..), encoding)
                next
              end

              return false unless split = split_qualified_name(name)

              prefix, local_name = split
              return false unless valid_name?(local_name, encoding)
              return false if prefix && !(valid_name?(prefix, encoding) && bindings.key?(prefix))

              key = [prefix && bindings[prefix], local_name]
              return false if expanded.key?(key)

              expanded[key] = true
            end
            true
          end

          # Resolves the root element's name against the tag's own bindings: the default
          # namespace for an unprefixed name, the prefix's binding otherwise. An unbound
          # prefix or invalid name is a namespace error.
          def resolve_name(qualified_name, bindings, encoding)
            return nil unless split = split_qualified_name(qualified_name)

            prefix, local_name = split
            return nil unless valid_name?(local_name, encoding)
            return nil if prefix == "xmlns"
            return nil if prefix && !(valid_name?(prefix, encoding) && bindings.key?(prefix))

            [prefix ? bindings[prefix] : bindings[nil], local_name]
          end
      end
    end
  end
end
