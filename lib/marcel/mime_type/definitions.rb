require 'mimemagic'
require 'mimemagic/overlay'

MimeMagic.add "text/plain", extensions: %w( txt asc )
MimeMagic.add "image/vnd.adobe.photoshop", magic: [[0, "8BPS"]], extensions: %w( psd psb )

MimeMagic.add "application/vnd.apple.pages", extensions: %w( pages )
MimeMagic.add "application/vnd.apple.numbers", extensions: %w( numbers )
MimeMagic.add "application/vnd.apple.keynote", extensions: %w( key )
