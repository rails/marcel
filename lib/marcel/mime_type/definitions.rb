require 'mimemagic'
require 'mimemagic/overlay'

Marcel::MimeType.add "text/plain", extensions: %w{ txt asc }
Marcel::MimeType.add "image/vnd.adobe.photoshop", magic: [[0, "8BPS"]], extensions: %w( psd psb )

Marcel::MimeType.add "application/vnd.apple.pages", extensions: %w( pages )
Marcel::MimeType.add "application/vnd.apple.numbers", extensions: %w( numbers )
Marcel::MimeType.add "application/vnd.apple.keynote", extensions: %w( key )
