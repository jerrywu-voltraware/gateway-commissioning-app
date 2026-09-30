# Local iOS builds

The Android `tools/build_apk.ps1 -Env prod` reads `.secrets/prod.env` and
converts its CA file into a Flutter define. Xcode Run alone does not read that
file. The iOS helper provides the equivalent preparation on the Mac.

Required local files (already excluded from Git):

- `.secrets/prod.env`: the existing production `APP_BACKEND_KEY` and `API_BASE`,
  with optional `API_CERT_SHA256`. Parsing follows the Android script:
  `KEY=VALUE`, surrounding whitespace trimmed, `#`/`!` comment lines ignored.
- `.secrets/ca.crt`: the existing public CA, verified against the Windows/Android
  DER SHA-256 fingerprint
  `A8FD32298C18E9C43AC7AD00D8F5F6D32335C42696CFA682C8C5B81A3517C24F`.
  No private key is needed. The Windows `API_CA_FILE` value is preserved;
  this helper uses the Mac copy instead of the Windows sibling-checkout path.

Commands, from the APP_v2 root:

```sh
ruby tools/build_ios.rb --check
ruby tools/build_ios.rb --configure
ruby tools/build_ios.rb --build
```

`--check` (also the default) is read-only. It prints readiness booleans and the
public CA fingerprint. It does not invoke Flutter or write any build settings.

`--configure` updates Flutter's generated Xcode settings for a debug build;
after it succeeds, Xcode Run builds/signs/installs using the selected device and
team. `--build` also compiles an unsigned debug app and does not install it.
Both commands use existing dependencies (`--no-pub`). Neither modifies the
Apple signing team or system certificate trust.

Before an agent runs either modifying mode in this handoff, obtain the requested
one-time confirmation to include the existing production backend credential in
local iOS build configuration/artifacts for production backend access. The
helper does not create new credentials, upload configuration, push, or publish.

The temporary JSON has mode 0600 and is deleted when Flutter returns. Generated
Xcode files and the compiled app still contain the credential (base64 is not
encryption). Do not share those files or commit them. Raw Flutter output is
withheld rather than printed or saved because it may echo build defines.

Re-run the helper after changing the local settings or after a plain
`flutter run/build` replaces the generated defines. Merely copying prod.env or
ca.crt and pressing Xcode Run does not perform this preparation.
