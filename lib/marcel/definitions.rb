require 'mimemagic'

MAGIC_DEFINITIONS = [
  ["image/vnd.adobe.photoshop", [[0, "8BPS"]]]
]

MAGIC_DEFINITIONS.each do |(type, magic)|
  MimeMagic.add(type, magic: magic)
end
