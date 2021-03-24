Marcel::MimeType.extend "text/plain", extensions: %w( txt asc )

Marcel::MimeType.extend "application/illustrator", parents: "application/pdf"
Marcel::MimeType.extend "image/vnd.adobe.photoshop", magic: [[0, "8BPS"]], extensions: %w( psd psb )

Marcel::MimeType.extend "application/vnd.ms-excel", parents: "application/x-ole-storage"
Marcel::MimeType.extend "application/vnd.ms-powerpoint", parents: "application/x-ole-storage"

Marcel::MimeType.extend "application/vnd.openxmlformats-officedocument.wordprocessingml.document", parents: "application/zip"
Marcel::MimeType.extend "application/vnd.openxmlformats-officedocument.wordprocessingml.template", parents: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
Marcel::MimeType.extend "application/vnd.ms-word.document.macroenabled.12", parents: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
Marcel::MimeType.extend "application/vnd.ms-word.template.macroenabled.12", parents: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"

Marcel::MimeType.extend "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", parents: "application/zip"
Marcel::MimeType.extend "application/vnd.openxmlformats-officedocument.spreadsheetml.template", parents: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
Marcel::MimeType.extend "application/vnd.ms-excel.sheet.macroenabled.12", parents: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
Marcel::MimeType.extend "application/vnd.ms-excel.template.macroenabled.12", parents: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
Marcel::MimeType.extend "application/vnd.ms-excel.addin.macroenabled.12", parents: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
Marcel::MimeType.extend "application/vnd.ms-excel.sheet.binary.macroenabled.12", parents: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

Marcel::MimeType.extend "application/vnd.openxmlformats-officedocument.presentationml.presentation", parents: "application/zip"
Marcel::MimeType.extend "application/vnd.openxmlformats-officedocument.presentationml.template", parents: "application/vnd.openxmlformats-officedocument.presentationml.presentation"
Marcel::MimeType.extend "application/vnd.openxmlformats-officedocument.presentationml.slideshow", parents: "application/vnd.openxmlformats-officedocument.presentationml.presentation"
Marcel::MimeType.extend "application/vnd.ms-powerpoint.addin.macroenabled.12", parents: "application/vnd.openxmlformats-officedocument.presentationml.presentation"
Marcel::MimeType.extend "application/vnd.ms-powerpoint.presentation.macroenabled.12", parents: "application/vnd.openxmlformats-officedocument.presentationml.presentation"
Marcel::MimeType.extend "application/vnd.ms-powerpoint.template.macroenabled.12", parents: "application/vnd.openxmlformats-officedocument.presentationml.presentation"
Marcel::MimeType.extend "application/vnd.ms-powerpoint.slideshow.macroenabled.12", parents: "application/vnd.openxmlformats-officedocument.presentationml.presentation"

Marcel::MimeType.extend "application/vnd.apple.pages", extensions: %w( pages ), parents: "application/zip"
Marcel::MimeType.extend "application/vnd.apple.numbers", extensions: %w( numbers ), parents: "application/zip"
Marcel::MimeType.extend "application/vnd.apple.keynote", extensions: %w( key ), parents: "application/zip"

Marcel::MimeType.extend "image/vnd.dwg", magic: [[0, "AC10"]]

Marcel::MimeType.extend "image/heif", magic: [[4, "ftypmif1"]], extensions: %w( heif )
Marcel::MimeType.extend "image/heic", magic: [[4, "ftypheic"]], extensions: %w( heic )

# Backwards compat overrides from MiniMime migration
Marcel::MimeType.extend "text/x-log", extensions: %w( log )
Marcel::MimeType.extend "application/sql", extensions: %w( sql )
Marcel::MimeType.extend "audio/flac", extensions: %w( flac )
Marcel::MimeType.extend "image/x-eps", extensions: %w( eps )
Marcel::MimeType.extend "video/mp4", extensions: %w( mp4 )
Marcel::MimeType.extend "image/bmp", extensions: %w( bmp )
Marcel::MimeType.extend "application/vnd.adobe.flash.movie", extensions: %w( swf )
