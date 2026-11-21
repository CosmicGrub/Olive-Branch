// OLIVE BRANCH — the shapes of the names a backup uses on any destination. UNVERIFIED on a device; pure Dart.
// A name is checked before it is ever put into a file path or a URL.

final RegExp _setRe = RegExp(r'^[0-9a-f]{32}$');
final RegExp _chunkRe = RegExp(r'^[0-9a-f]{64}$');
final RegExp _manifestRe = RegExp(r'^[0-9]{10}-[0-9a-f]{8}$');

bool isSetId(String s) => _setRe.hasMatch(s);
bool isChunkId(String s) => _chunkRe.hasMatch(s);
bool isManifestName(String s) => _manifestRe.hasMatch(s);
