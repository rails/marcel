class Marcel::MimeType::Subclasses
  class << self
    def for(type)
      subclasses[type]
    end

    private
      def subclasses
        @subclasses ||= Hash.new([])
      end
  end

  subclasses["application/vnd.openxmlformats-officedocument.wordprocessingml.document"] = %w(
    application/vnd.openxmlformats-officedocument.wordprocessingml.template
    application/vnd.ms-word.document.macroenabled.12
    application/vnd.ms-word.template.macroenabled.12
  )

  subclasses["application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"] = %w(
    application/vnd.openxmlformats-officedocument.spreadsheetml.template
    application/vnd.ms-excel.sheet.macroenabled.12
    application/vnd.ms-excel.template.macroenabled.12
    application/vnd.ms-excel.addin.macroenabled.12
    application/vnd.ms-excel.sheet.binary.macroenabled.12
  )

  subclasses["application/vnd.openxmlformats-officedocument.presentationml.presentation"] = %w(
    application/vnd.openxmlformats-officedocument.presentationml.template
    application/vnd.openxmlformats-officedocument.presentationml.slideshow
    application/vnd.ms-powerpoint.addin.macroenabled.12
    application/vnd.ms-powerpoint.presentation.macroenabled.12
    application/vnd.ms-powerpoint.template.macroenabled.12
    application/vnd.ms-powerpoint.slideshow.macroenabled.12
  )

  subclasses["application/x-ole-storage"] = %w(
    application/vnd.ms-excel
  )

  subclasses["application/zip"] = %w(
    application/vnd.apple.pages
    application/vnd.apple.keynote
    application/vnd.apple.numbers
  )
end
