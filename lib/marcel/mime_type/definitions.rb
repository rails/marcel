require 'mimemagic'
require 'mimemagic/overlay'

MimeMagic.add "text/plain", extensions: %w{ txt asc }
MimeMagic.add "image/vnd.adobe.photoshop", magic: [[0, "8BPS"]], extensions: %w{ psd psb }
