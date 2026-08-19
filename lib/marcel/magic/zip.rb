# frozen_string_literal: true

module Marcel
  class Magic
    # Procedural refinement of ZIP-based container types.
    #
    # The declarative magic tables scan a bounded prefix of the file (matchers are capped at
    # 64KB offsets when the tables are generated), so ZIP containers whose distinguishing
    # members are catalogued later in the archive — such as OOXML documents with
    # [Content_Types].xml stored past the 64KB mark — fall back to their generic container
    # type. This module instead parses the ZIP central directory, a bounded read from the end
    # of the file, to recover the specific document type, including macro-enabled variants,
    # which no prefix bytes can distinguish.
    module Zip
      EOCD_SIGNATURE = "PK\x05\x06".b
      ZIP64_EOCD_SIGNATURE = "PK\x06\x06".b
      ZIP64_EOCD_LOCATOR_SIGNATURE = "PK\x06\x07".b
      CENTRAL_DIRECTORY_SIGNATURE = "PK\x01\x02".b

      EOCD_SIZE = 22
      ZIP64_EOCD_SIZE = 56
      ZIP64_EOCD_LOCATOR_SIZE = 20
      MAX_COMMENT_SIZE = 0xFFFF

      # The end-of-central-directory record sits at most a maximal comment from the end of
      # the file, possibly preceded by a Zip64 locator.
      MAX_EOCD_SEARCH = EOCD_SIZE + MAX_COMMENT_SIZE + ZIP64_EOCD_LOCATOR_SIZE

      # A malformed trailer full of EOCD signature bytes could otherwise force a quadratic
      # backward scan; real archives find the record on the first candidate.
      MAX_EOCD_CANDIDATES = 64

      CENTRAL_DIRECTORY_HEADER_SIZE = 46
      MAX_CENTRAL_DIRECTORY_READ = 1 << 20
      MAX_ENTRIES = 8192

      # Container types a central directory listing can make more specific.
      REFINABLE_TYPES = [
        "application/zip",
        "application/x-tika-ooxml",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "application/vnd.openxmlformats-officedocument.presentationml.presentation"
      ].freeze

      # Standardised OPC part names identifying each OOXML document family:
      # main part, macro part, and the types each implies.
      DOCUMENT_FAMILIES = [
        [ "word/document.xml", "word/vbaProject.bin",
          "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
          "application/vnd.ms-word.document.macroenabled.12" ],
        [ "xl/workbook.xml", "xl/vbaProject.bin",
          "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
          "application/vnd.ms-excel.sheet.macroenabled.12" ],
        [ "ppt/presentation.xml", "ppt/vbaProject.bin",
          "application/vnd.openxmlformats-officedocument.presentationml.presentation",
          "application/vnd.ms-powerpoint.presentation.macroenabled.12" ]
      ].freeze

      DISCRIMINATING_PARTS = DOCUMENT_FAMILIES.flat_map { |main, macro, *| [main, macro] }.freeze

      class << self
        # Returns a more specific type than +base_type+ if the IO's ZIP central directory
        # identifies one, or +base_type+ unchanged. Unseekable IOs, partial reads and
        # malformed archives refine nothing: the base type stands.
        def refine(io, base_type)
          return base_type unless REFINABLE_TYPES.include?(base_type)

          io = StringIO.new(io.to_s) unless io.respond_to?(:read)
          return base_type unless io.respond_to?(:seek) && io.respond_to?(:size)

          parts = begin
            discriminating_parts(io)
          rescue StandardError
            nil
          ensure
            begin
              io.rewind
            rescue StandardError
              nil
            end
          end

          parts ? classify(parts, base_type) : base_type
        end

        private

          def classify(parts, base_type)
            DOCUMENT_FAMILIES.each do |main_part, macro_part, type, macro_type|
              return parts.include?(macro_part) ? macro_type : type if parts.include?(main_part)
            end
            base_type
          end

          # Reads the archive's central directory and returns the OOXML part names it
          # catalogues, or nil if no well-formed central directory is found.
          def discriminating_parts(io)
            size = io.size
            return nil unless size.is_a?(Integer) && size >= EOCD_SIZE

            tail_size = [size, MAX_EOCD_SEARCH].min
            io.seek(size - tail_size)
            tail = io.read(tail_size)
            return nil unless tail && tail.bytesize == tail_size
            tail = tail.dup.force_encoding(Encoding::BINARY)

            eocd_pos = locate_eocd(tail)
            return nil unless eocd_pos

            entries, directory_size, directory_offset = parse_eocd(io, tail, eocd_pos)
            return nil unless entries && directory_offset + directory_size <= size

            read_parts(io, entries, directory_size, directory_offset)
          end

          # Scans backward through the file's tail for the end-of-central-directory record,
          # validating each candidate signature against its comment length.
          def locate_eocd(tail)
            pos = tail.bytesize - EOCD_SIZE
            MAX_EOCD_CANDIDATES.times do
              return nil unless pos && pos >= 0 && (pos = tail.rindex(EOCD_SIGNATURE, pos))
              comment_size = tail[pos + 20, 2].unpack1("v")
              return pos if pos + EOCD_SIZE + comment_size == tail.bytesize
              pos -= 1
            end
            nil
          end

          # Returns [entry count, central directory size, central directory offset], following
          # the Zip64 records when the classic fields overflow. Multi-disk archives and
          # malformed records return nil.
          def parse_eocd(io, tail, eocd_pos)
            disk, directory_disk, entries, directory_size, directory_offset =
              tail[eocd_pos + 4, 16].unpack("vvx2vVV")
            return nil unless disk == 0 && directory_disk == 0

            if entries == 0xFFFF || directory_size == 0xFFFFFFFF || directory_offset == 0xFFFFFFFF
              parse_zip64_eocd(io, tail, eocd_pos)
            else
              [entries, directory_size, directory_offset]
            end
          end

          def parse_zip64_eocd(io, tail, eocd_pos)
            locator_pos = eocd_pos - ZIP64_EOCD_LOCATOR_SIZE
            return nil if locator_pos < 0 || tail[locator_pos, 4] != ZIP64_EOCD_LOCATOR_SIGNATURE

            locator_disk, zip64_eocd_offset, total_disks = tail[locator_pos + 4, 16].unpack("VQ<V")
            return nil unless locator_disk == 0 && total_disks == 1

            io.seek(zip64_eocd_offset)
            record = io.read(ZIP64_EOCD_SIZE)
            return nil unless record && record.bytesize == ZIP64_EOCD_SIZE
            record = record.dup.force_encoding(Encoding::BINARY)
            return nil unless record[0, 4] == ZIP64_EOCD_SIGNATURE

            disk, directory_disk, _, entries, directory_size, directory_offset =
              record[16, 40].unpack("VVQ<Q<Q<Q<")
            return nil unless disk == 0 && directory_disk == 0

            [entries, directory_size, directory_offset]
          end

          # Walks central directory entries, collecting the OOXML part names that
          # discriminate between document families. Reads and entry counts are bounded;
          # the walk stops early once a family and its macro part are both seen.
          def read_parts(io, entries, directory_size, directory_offset)
            io.seek(directory_offset)
            directory = io.read([directory_size, MAX_CENTRAL_DIRECTORY_READ].min)
            return nil unless directory
            directory = directory.dup.force_encoding(Encoding::BINARY)

            parts = []
            pos = 0
            [entries, MAX_ENTRIES].min.times do
              break unless pos + CENTRAL_DIRECTORY_HEADER_SIZE <= directory.bytesize &&
                directory[pos, 4] == CENTRAL_DIRECTORY_SIGNATURE

              name_size, extra_size, comment_size = directory[pos + 28, 6].unpack("vvv")
              name = directory[pos + CENTRAL_DIRECTORY_HEADER_SIZE, name_size]
              break unless name && name.bytesize == name_size

              parts << name if DISCRIMINATING_PARTS.include?(name)
              break if complete?(parts)

              pos += CENTRAL_DIRECTORY_HEADER_SIZE + name_size + extra_size + comment_size
            end
            parts
          end

          # A main part plus its macro part is as specific as classification gets.
          def complete?(parts)
            DOCUMENT_FAMILIES.any? do |main_part, macro_part, *|
              parts.include?(main_part) && parts.include?(macro_part)
            end
          end
      end
    end
  end
end
