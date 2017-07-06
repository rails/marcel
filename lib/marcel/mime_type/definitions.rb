require 'mimemagic'
require 'mimemagic/overlay'

Marcel::MimeType.add "text/plain", extensions: %w{ txt asc }

Marcel::MimeType.add "application/illustrator", parents: "application/pdf"
Marcel::MimeType.add "image/vnd.adobe.photoshop", magic: [[0, "8BPS"]], extensions: %w( psd psb )

Marcel::MimeType.add "application/vnd.ms-excel", parents: "application/x-ole-storage"

Marcel::MimeType.add "application/vnd.openxmlformats-officedocument.wordprocessingml.document", parents: "application/zip"
Marcel::MimeType.add "application/vnd.openxmlformats-officedocument.wordprocessingml.template", parents: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
Marcel::MimeType.add "application/vnd.ms-word.document.macroenabled.12", parents: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
Marcel::MimeType.add "application/vnd.ms-word.template.macroenabled.12", parents: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"

Marcel::MimeType.add "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", parents: "application/zip"
Marcel::MimeType.add "application/vnd.openxmlformats-officedocument.spreadsheetml.template", parents: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
Marcel::MimeType.add "application/vnd.ms-excel.sheet.macroenabled.12", parents: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
Marcel::MimeType.add "application/vnd.ms-excel.template.macroenabled.12", parents: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
Marcel::MimeType.add "application/vnd.ms-excel.addin.macroenabled.12", parents: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
Marcel::MimeType.add "application/vnd.ms-excel.sheet.binary.macroenabled.12", parents: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

Marcel::MimeType.add "application/vnd.openxmlformats-officedocument.presentationml.presentation", parents: "application/zip"
Marcel::MimeType.add "application/vnd.openxmlformats-officedocument.presentationml.template", parents: "application/vnd.openxmlformats-officedocument.presentationml.presentation"
Marcel::MimeType.add "application/vnd.openxmlformats-officedocument.presentationml.slideshow", parents: "application/vnd.openxmlformats-officedocument.presentationml.presentation"
Marcel::MimeType.add "application/vnd.ms-powerpoint.addin.macroenabled.12", parents: "application/vnd.openxmlformats-officedocument.presentationml.presentation"
Marcel::MimeType.add "application/vnd.ms-powerpoint.presentation.macroenabled.12", parents: "application/vnd.openxmlformats-officedocument.presentationml.presentation"
Marcel::MimeType.add "application/vnd.ms-powerpoint.template.macroenabled.12", parents: "application/vnd.openxmlformats-officedocument.presentationml.presentation"
Marcel::MimeType.add "application/vnd.ms-powerpoint.slideshow.macroenabled.12", parents: "application/vnd.openxmlformats-officedocument.presentationml.presentation"

Marcel::MimeType.add "application/vnd.apple.pages", extensions: %w( pages ), parents: "application/zip"
Marcel::MimeType.add "application/vnd.apple.numbers", extensions: %w( numbers ), parents: "application/zip"
Marcel::MimeType.add "application/vnd.apple.keynote", extensions: %w( key ), parents: "application/zip"
