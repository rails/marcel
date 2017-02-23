# Marcel

Determines file mime types given the file data, the file name and (optionally)
a declared content type (perhaps given as a request header).

It uses all of magic numbers (via mimemagic), the declared type, and the name
to determine the type.

Usage:

    Marcel::MimeType.for File.open("example.gif"), name: "example.gif", declared_type: "application/octet-stream"

