# frozen_string_literal: true

html_magic = [
  [0..4096, %r{\A(?:\xEF\xBB\xBF)?[ \t\r\n\f]*(?:<\?xml(?:[ \t\r\n\f]+(?:[^?]|\?(?!>))*)?\?>[ \t\r\n\f]*)?(?:<!--(?:[^-]|-(?!->))*-->[ \t\r\n\f]*)*(?:<!DOCTYPE[ \t\r\n\f]+html(?=[ \t\r\n\f>])|<html(?=[ \t\r\n\f>]))}imn],
]

xhtml_magic = [
  [0..4096, %r{
    \A
    (?:\xEF\xBB\xBF)?[ \t\r\n\f]*
    (?:<\?xml(?:[ \t\r\n\f]+(?:[^?]|\?(?!>))*)?\?>[ \t\r\n\f]*)?
    (?:<!--(?:[^-]|-(?!->))*-->[ \t\r\n\f]*)*
    (?:
      <!DOCTYPE[ \t\r\n\f]+html(?:[ \t\r\n\f]+[^>]*)?>[ \t\r\n\f]*
      (?:<!--(?:[^-]|-(?!->))*-->[ \t\r\n\f]*)*
    )?
    <html(?=[ \t\r\n\f>])
    (?:
      [ \t\r\n\f]+
      (?!xmlns[ \t\r\n\f]*=)
      [A-Za-z_:][A-Za-z0-9_.:-]*
      [ \t\r\n\f]*=[ \t\r\n\f]*
      (?:"[^"]*"|'[^']*')
    )*
    [ \t\r\n\f]+xmlns[ \t\r\n\f]*=[ \t\r\n\f]*
    (?:"http://www\.w3\.org/1999/xhtml"|'http://www\.w3\.org/1999/xhtml')
  }xmn],
]

[
  ["text/html", html_magic],
  ["application/xhtml+xml", xhtml_magic],
].each do |type, magic|
  extensions = Marcel::TYPE_EXTS[type]
  parents = Marcel::TYPE_PARENTS[type]

  Marcel::Magic.remove(type)
  Marcel::Magic.add(type, extensions: extensions, parents: parents, magic: magic)
end
