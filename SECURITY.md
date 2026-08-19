# Security Policy

Please do not report suspected security vulnerabilities in a public GitHub issue. Report them privately through the [Ruby on Rails security process](https://rubyonrails.org/security).

Marcel is a best-effort MIME type labeler, not a file validator or security boundary. It labels content; it does not sanitize it, and a result other than `text/html` is not proof that the bytes are safe markup. Serve untrusted uploads as attachments, through a strict inline allowlist, or from a separate untrusted origin. Set an explicit `Content-Type` from a trusted source and `X-Content-Type-Options: nosniff` as additional controls. See the Security considerations section of the README for details.

Include the Marcel version, the inputs supplied to `Marcel::MimeType.for` (bytes, filename, declared type, and whether the bytes are a partial read), the returned type, and the downstream security decision in the report.
