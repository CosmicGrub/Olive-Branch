// OLIVE BRANCH — Flutter client, API surface.
//
// UNVERIFIED: no Dart/Flutter toolchain exists in this repository, so this file
// is not compiled or analysed. See MASTERFILE §20.2. Every endpoint string here
// is however checked against the registered API routes by
// packages/api/test/contract.test.mjs, so the two cannot drift silently.

class OliveApi {
  OliveApi(this.baseUrl, this.sessionToken);
  final String baseUrl;
  final String sessionToken;

  // --- identity -----------------------------------------------------------
  static const me = '/v1/me';

  // --- time engine (§7.2) -------------------------------------------------
  static const childNow    = '/v1/children/:childId/now';
  static const childRibbon = '/v1/children/:childId/ribbon';
  static const childOverlap = '/v1/children/:childId/overlap';

  // --- async delivery (§7.3) ---------------------------------------------
  static const inbox    = '/v1/children/:childId/inbox';
  static const messages = '/v1/children/:childId/messages';
  static const batches  = '/v1/children/:childId/batches';

  // --- child agency (§7.10) ----------------------------------------------
  static const ping    = '/v1/children/:childId/ping';
  static const journal = '/v1/children/:childId/journal';

  // --- coordination (§7.7) -----------------------------------------------
  static const medications   = '/v1/children/:childId/medications';
  static const emergencyCard = '/v1/children/:childId/emergency-card';

  // --- guarded by escalation (§8.3) --------------------------------------
  static const settings = '/v1/children/:childId/settings';
}
