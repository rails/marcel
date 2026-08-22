# Marcel

Marcel chooses the most appropriate content type for a file by inspecting its contents, the declared MIME type (perhaps passed as a Content-Type header), and the file extension.

Marcel checks, in order:

1. The "magic bytes" sniffed from the file contents.
2. The declared type, typically provided in a Content-Type header on an uploaded file, if it is a valid single media type other than the `application/octet-stream` default.
3. The filename extension.
4. Conservative fallback to the indeterminate `application/octet-stream` default.

At each step, the most specific MIME subtype is selected. This allows the declared type and file extension to refine the parent type sniffed from the file contents, but not conflict with it. For example, if "file.csv" has declared type `text/plain`, `text/csv` is returned since it's a more specific subtype of `text/plain`. Similarly, Adobe Illustrator files are PDFs internally, so magic byte sniffing indicates `application/pdf` which is refined to `application/illustrator` by the `ai` file extension. But a PDF named "image.png" will still be detected as `application/pdf` since `image/png` is not a subtype. Specificity is based on MIME taxonomy, not proof that a file conforms to the selected type; see Security considerations below.

Declared types may include parameters and surrounding HTTP whitespace. As a deliberate compatibility recovery, Marcel tolerates a single trailing semicolon. It ignores other malformed and comma-separated declared types rather than choosing one value from a list.

## Security considerations

Marcel is a best-effort file type labeler, not a file validator or a security boundary. The declared type and filename are caller-provided hints. A syntactically valid but unregistered declared type may be returned as-is when content magic does not conflict with it.

When content magic identifies a ZIP-based container, Marcel reads the archive's central directory listing — a bounded read from the end of seekable content — to distinguish Office document families and their macro-enabled variants by catalogued part names such as `xl/vbaProject.bin`. It reads only member names, not member contents, and does not verify format conformance or archive contents. A non-macro label is not proof that macros are absent: unseekable or truncated content, malformed archives, and formats catalogued under other names skip this refinement, and hints may still refine the generic container type. Likewise, `Marcel::Magic#text?` and `#image?` describe MIME taxonomy, not whether content is safe.

When content magic identifies generic XML, Marcel scans a bounded 64 KiB prefix for the document's root element and refines the label by the root's namespace and local name, following Apache Tika's root-element rules: feeds, KML, property lists, XSLT, XHTML and Office 2003 XML among others. The scan resolves no entities, DTD declarations, or external resources; as with Tika's namespace-aware SAX extraction, a prolog or root start-tag that is not well-formed at the token level — including namespace rules, forbidden characters, and bytes invalid in the declared encoding — refines nothing. Like Tika, it labels un-namespaced `<body>`, `<p>`, `<script>`, `<frameset>`, `<iframe>` and `<link>` roots as `text/html`. Prologs it cannot read, roots beyond the prefix, and unknown roots keep the generic `application/xml` label, which is therefore not proof that the content is inert markup.

Do not use Marcel's result by itself to decide whether content is safe to execute, parse with privileged features, or render inline. Apply the controls required by the consuming parser or renderer independently of the detected label.

Magic rules inspect bounded samples, so results can differ when a caller provides only a prefix. HTML detection recognizes document-opening `<html>` and `<!DOCTYPE html>` markers, not every fragment that can contain active markup. A result other than `text/html` is therefore not proof that the bytes are safe markup.

Serve untrusted uploads as attachments, restrict inline rendering to a small vetted allowlist, or isolate them on a separate untrusted origin. Also set an explicit `Content-Type` from a trusted source and `X-Content-Type-Options: nosniff`; those headers do not make correctly labelled active content safe to render inline. Rails Active Storage applies separate content-type and disposition controls when serving blobs. Call `Marcel::Magic.by_magic` directly when caller-provided filename and declared-type hints need to be evaluated separately from content magic.

Callers should apply their normal request and metadata size limits before invoking Marcel. Declared MIME types larger than 8 KiB are ignored. Content IOs must support `rewind`; buffer pipes and sockets before detection.

## Usage

```ruby
# Magic bytes sniffing alone
Marcel::MimeType.for Pathname.new("example.gif")
#  => "image/gif"

File.open "example.gif" do |file|
  Marcel::MimeType.for file
end
#  => "image/gif"

# Magic bytes with filename fallback
Marcel::MimeType.for Pathname.new("unrecognisable-data"), name: "example.pdf"
#  => "application/pdf"

# File extension alone
Marcel::MimeType.for extension: ".pdf"
#  => "application/pdf"

# Magic bytes, declared type, and filename together
Marcel::MimeType.for Pathname.new("unrecognisable-data"), name: "example", declared_type: "image/png"
#  => "image/png"

# Conservative fallback to application/octet-stream
Marcel::MimeType.for StringIO.new(File.read "unrecognisable-data")
#  => "application/octet-stream"
```

## Extending

Custom file types may be added with `Marcel::MimeType.extend`:

```ruby
Marcel::MimeType.extend "text/custom", extensions: %w( customtxt )
Marcel::MimeType.for name: "file.customtxt"
#  => "text/custom"
```

Registration mutates a process-global registry. Add custom types during single-threaded application boot, before concurrent detection begins. Extension collisions replace the existing mapping, and removing the custom type does not restore a mapping it replaced.

## Motivation

Marcel was extracted from Basecamp's file detection heuristics. The aim is to provide sensible, conservative, "do what I expect" results for typical file handling. Test fixtures have been added for many common file types, including those typically encountered by Basecamp.


## Contributing

Marcel generates MIME lookup tables with `bundle exec rake update`. MIME types are seeded from data found in `data/*.xml`. The Apache Tika download and committed `data/tika.xml` are verified against the commit and checksum in `script/download_tika_data.rb`; review and update both values when refreshing it. Custom MIMEs may be added to `data/custom.xml`, while code-defined overrides live in the definitions files under `lib/marcel`.

Marcel follows the same contributing guidelines as [rails/rails](https://github.com/rails/rails#contributing).


## Testing

The main test fixture files are split into two folders, those that can be recognised by magic bytes, and those that can only be recognised by name. Even though strictly unnecessary, the fixtures in both folders should all be valid files of the type they represent.


## License

Marcel itself is released under the terms of the MIT License. See the MIT-LICENSE file for details.

Portions of Marcel are adapted from the [mimemagic] gem, released under the terms of the MIT License.

Marcel's magic signature data is adapted from [Apache Tika](https://tika.apache.org), released under the terms of the Apache License. See the APACHE-LICENSE file for details.

[mimemagic]: https://github.com/mimemagicrb/mimemagic
