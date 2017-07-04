# Marcel

Marcel attempts to choose the most appropriate content type for a given file by looking at the binary data, the filename, and any declared type (perhaps passed as a request header):

Its basic usage is:

    Marcel::MimeType.for File.open("example.gif"), name: "example.gif", declared_type: "application/octet-stream"

By preference, Marcel will usually use the magic number data in the passed in file to determine the type. If this doesn't work, it uses the type gleaned from the filename, and finally the declared type. If none of these match, it returns "application/octet-stream"

For example:

    Marcel::MimeType.for File.open("example.gif")
      => "image/gif"

    Marcel::MimeType.for File.open("unrecognisable-data"), name: "example.pdf"
      => "application/pdf"

    Marcel::MimeType.for File.open("unrecognisable-data"), name: "example", declared_type: "image/png"
      => "image/png"

    Marcel::MimeType.for File.open("unrecognisable-data"), name: "example", declared_type: nil
      => "application/octet-stream"

Some types aren't easily recognised solely by magic number data. For example Adobe Illustrator files have the same magic number as PDFs (and can usually even be viewed in PDF viewers!). For these types, Marcel uses both the magic number data and the file name to work out the type:

    Marcel::MimeType.for File.open("example.ai"), name: "example.ai"
      => "application/illustrator"

This only happens when the type from the filename is a more specific type of that from the magic number. If it isn't the magic number alone is used.

    Marcel::MimeType.for File.open("example.png"), name: "example.ai"
      => "image/png"
    # As "application/illustrator" is not a more specific type of "image/png", the filename is ignored

`Marcel::MimeType.for` has no required arguments, and will attempt to make the best guess given whatever is passed to
it:

    Marcel::MimeType.for name: "example.pdf"
      => "application/pdf"

    Marcel::MimeType.for extension: ".pdf"
      => "application/pdf"

    Marcel::MimeType.for
      => "application/pdf"


