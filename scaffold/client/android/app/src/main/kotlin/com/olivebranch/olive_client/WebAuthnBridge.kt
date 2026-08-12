// OLIVE BRANCH — Android WebAuthn/passkey bridge. §7.1, §8.1, §11.
//
// Real androidx.credentials Credential Manager integration -- the guardian
// side's actual platform passkey ceremony, on the SAME method-channel-per-
// feature pattern KioskBridge.kt already established: channel name
// app.olive/webauthn (mirroring app.olive/kiosk), wired into
// MainActivity.kt's configureFlutterEngine exactly the same way, real error
// codes crossing the channel boundary via MethodChannel.Result#error()
// rather than a folded-into-success error map.
//
// API-LEVEL TENSION, DOCUMENTED RATHER THAN SILENTLY RESOLVED: this app's
// real minSdk is 26 (app/build.gradle.kts, driven by the Jitsi SDK's own
// manifest floor -- see that file's own comment). Credential Manager's
// passkey ceremony genuinely needs API 28+ to create/get a credential for
// real -- confirmed against developer.android.com/identity/passkeys
// (Android 9+ required for passkeys), not assumed -- below that the
// platform providers either have nothing to offer or the library's own
// "fails gracefully" behavior kicks in, which is not the same thing as a
// clear, distinct, Dart-visible reason. Raising minSdk to 28 to make this
// tension disappear would drop support for any real Android 8.0/8.1 device
// this app is already installed on -- a bigger call than a single feature's
// bridge gets to make unilaterally. So: a runtime Build.VERSION.SDK_INT
// check below (MIN_PASSKEY_SDK_INT), not a minSdk bump. Below API 28 this
// reports 'api_level_too_low' honestly instead of attempting the ceremony.
//
// DISCOVERABLE (RESIDENT) CREDENTIAL, DELIBERATELY: server/index.mjs's
// webauthnLoginChallenge() returns only {challenge, rpId} -- no
// allowCredentials list -- and this bridge's authenticate() is called with
// no credentialId either (see webauthn_channel.dart). The only way
// GetPublicKeyCredentialOption can find anything at all under those
// constraints is if the credential register() creates is discoverable by
// rpId alone, so registration requests residentKey:"required". This is a
// real, necessary consequence of the server's own "bare userId hint, no
// server-side credential lookup" design (see server/index.mjs's own header
// comment on webauthnLoginChallenge), not an independent choice made here.
//
// ATTESTATION: requested as "none". packages/auth/src/attestation.ts's own
// header states its trust model is the device-bound public key, not the
// attestation chain -- attStmt's bytes are walked past structurally, never
// verified. A stronger attestation conveyance would buy nothing this server
// actually checks, and "none" is the broadest-compatibility choice.
package com.olivebranch.olive_client

import android.app.Activity
import android.os.Build
import android.util.Base64
import androidx.credentials.CreateCredentialResponse
import androidx.credentials.CreatePublicKeyCredentialRequest
import androidx.credentials.CreatePublicKeyCredentialResponse
import androidx.credentials.CredentialManager
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetPublicKeyCredentialOption
import androidx.credentials.PublicKeyCredential
import androidx.credentials.exceptions.CreateCredentialCancellationException
import androidx.credentials.exceptions.CreateCredentialException
import androidx.credentials.exceptions.CreateCredentialInterruptedException
import androidx.credentials.exceptions.CreateCredentialNoCreateOptionException
import androidx.credentials.exceptions.CreateCredentialProviderConfigurationException
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.GetCredentialInterruptedException
import androidx.credentials.exceptions.GetCredentialProviderConfigurationException
import androidx.credentials.exceptions.NoCredentialException
import androidx.credentials.exceptions.publickeycredential.CreatePublicKeyCredentialDomException
import androidx.credentials.exceptions.publickeycredential.GetPublicKeyCredentialDomException
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

object WebAuthnBridge {
    const val METHOD_CHANNEL = "app.olive/webauthn"

    // Method names -- mirrored in client/lib/webauthn_channel.dart.
    const val M_REGISTER     = "register"
    const val M_AUTHENTICATE = "authenticate"

    // The real, minimum API level at which androidx.credentials can create
    // or get a platform passkey for real -- see this file's header.
    private const val MIN_PASSKEY_SDK_INT = 28

    // kotlinx-coroutines-android is already a real transitive dependency
    // here (pulled in by androidx.credentials itself and by other plugins --
    // confirmed via `gradlew :app:dependencies` before writing this, not
    // assumed), so this adds no new dependency. Dispatchers.Main.immediate
    // because MethodChannel's own call already arrives on the main thread;
    // CredentialManager's suspend calls need it there to show system UI.
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    fun register(activity: Activity, methodChannel: MethodChannel) {
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                M_REGISTER -> handleRegister(activity, call, result)
                M_AUTHENTICATE -> handleAuthenticate(activity, call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handleRegister(
        activity: Activity, call: MethodCall, result: MethodChannel.Result,
    ) {
        if (Build.VERSION.SDK_INT < MIN_PASSKEY_SDK_INT) {
            result.error("api_level_too_low",
                "Passkeys need Android 9 (API 28) or higher; this device is API " +
                    "${Build.VERSION.SDK_INT}.", null)
            return
        }
        val challenge = call.argument<String>("challenge")
        val rpId = call.argument<String>("rpId")
        val userId = call.argument<String>("userId")
        val userName = call.argument<String>("userName")
        if (challenge == null || rpId == null || userId == null || userName == null) {
            result.error("bad_arguments",
                "register requires challenge, rpId, userId, userName.", null)
            return
        }

        val credentialManager = CredentialManager.create(activity)
        val request = CreatePublicKeyCredentialRequest(
            buildCreateRequestJson(challenge, rpId, userId, userName))

        scope.launch {
            try {
                // CredentialManager.createCredential(Context, CreateCredentialRequest):
                // CreateCredentialResponse -- a real suspend fun, confirmed against
                // the actual androidx.credentials:credentials:1.6.0 AAR's compiled
                // class (javap'd before writing this, not guessed from docs -- an
                // earlier doc-site fetch during this same pass produced a WRONG
                // import for CreatePublicKeyCredentialDomException that the real
                // .aar's class list caught).
                val response: CreateCredentialResponse =
                    credentialManager.createCredential(activity, request)
                val pkResponse = response as CreatePublicKeyCredentialResponse
                // registrationResponseJson is already the WebAuthn
                // RegistrationResponseJSON shape -- response.clientDataJSON and
                // response.attestationObject are ALREADY base64url strings, the
                // exact encoding server/routes.mjs's register/verify expects. No
                // re-encoding here.
                val respObj = JSONObject(pkResponse.registrationResponseJson)
                    .getJSONObject("response")
                result.success(mapOf(
                    "clientDataJSON" to respObj.getString("clientDataJSON"),
                    "attestationObject" to respObj.getString("attestationObject"),
                ))
            } catch (e: CreateCredentialCancellationException) {
                result.error("user_cancelled",
                    "The guardian dismissed the passkey prompt.", null)
            } catch (e: CreateCredentialNoCreateOptionException) {
                result.error("no_platform_authenticator",
                    "No platform authenticator is available on this device -- most " +
                        "likely no screen lock or biometric is configured yet.", null)
            } catch (e: CreateCredentialProviderConfigurationException) {
                result.error("provider_not_configured",
                    "No credential provider is configured on this device (Google " +
                        "Play services is missing or too old).", null)
            } catch (e: CreateCredentialInterruptedException) {
                result.error("interrupted",
                    "The passkey ceremony was interrupted; it can be retried.", null)
            } catch (e: CreatePublicKeyCredentialDomException) {
                // WebAuthn-spec DOM error -- e.domError.type names it exactly
                // (e.g. "NotAllowedError"), a real, distinct reason rather than a
                // folded-together generic failure.
                result.error("dom_error_${e.domError.type}", e.errorMessage?.toString(), null)
            } catch (e: CreateCredentialException) {
                result.error("create_credential_failed_${e.type}", e.errorMessage?.toString(), null)
            } catch (e: Exception) {
                result.error("unexpected_error", e.message, null)
            }
        }
    }

    private fun handleAuthenticate(
        activity: Activity, call: MethodCall, result: MethodChannel.Result,
    ) {
        if (Build.VERSION.SDK_INT < MIN_PASSKEY_SDK_INT) {
            result.error("api_level_too_low",
                "Passkeys need Android 9 (API 28) or higher; this device is API " +
                    "${Build.VERSION.SDK_INT}.", null)
            return
        }
        val challenge = call.argument<String>("challenge")
        val rpId = call.argument<String>("rpId")
        if (challenge == null || rpId == null) {
            result.error("bad_arguments", "authenticate requires challenge and rpId.", null)
            return
        }

        val credentialManager = CredentialManager.create(activity)
        val option = GetPublicKeyCredentialOption(buildGetOptionJson(challenge, rpId))
        // No allowCredentials narrowing -- see file header: login has no
        // credentialId to hand in, so this can only ever find a discoverable
        // (resident) credential, which register() above deliberately creates.
        //
        // preferImmediatelyAvailableCredentials(true) -- the real, verified
        // (javap'd against this project's actual androidx.credentials:
        // credentials:1.6.0 AAR, not assumed -- Builder() takes NO
        // constructor arguments; options are added via addCredentialOption(),
        // confirmed against the real compiled class after an earlier attempt
        // at Builder(listOf(option)) failed to even COMPILE against the real
        // AAR) mechanism for keeping this ceremony consistent with
        // registration's own platform-only posture. WebAuthn's
        // PublicKeyCredentialRequestOptionsJSON has no authenticatorAttachment
        // field at all (that concept only exists on the CREATE side, see
        // buildCreateRequestJson's own comment) -- this Builder flag is the
        // one real lever the GET side has, and without it the system
        // credential picker on a shared/kiosk device would still silently
        // offer a cross-device/roaming (hybrid/caBLE) option even though
        // every credential this app ever creates is platform-attached.
        val request = GetCredentialRequest.Builder()
            .addCredentialOption(option)
            .setPreferImmediatelyAvailableCredentials(true)
            .build()

        scope.launch {
            try {
                val response = credentialManager.getCredential(activity, request)
                val credential = response.credential as PublicKeyCredential
                val json = JSONObject(credential.authenticationResponseJson)
                val respObj = json.getJSONObject("response")
                result.success(mapOf(
                    // "id" is already base64url per the WebAuthn JSON spec --
                    // the same encoding webauthnCredentialById() looks up by.
                    "credentialId" to json.getString("id"),
                    "clientDataJSON" to respObj.getString("clientDataJSON"),
                    "authenticatorData" to respObj.getString("authenticatorData"),
                    "signature" to respObj.getString("signature"),
                ))
            } catch (e: GetCredentialCancellationException) {
                result.error("user_cancelled",
                    "The guardian dismissed the passkey prompt.", null)
            } catch (e: NoCredentialException) {
                result.error("no_platform_authenticator",
                    "No passkey for this account is available on this device.", null)
            } catch (e: GetCredentialProviderConfigurationException) {
                result.error("provider_not_configured",
                    "No credential provider is configured on this device (Google " +
                        "Play services is missing or too old).", null)
            } catch (e: GetCredentialInterruptedException) {
                result.error("interrupted",
                    "The passkey ceremony was interrupted; it can be retried.", null)
            } catch (e: GetPublicKeyCredentialDomException) {
                result.error("dom_error_${e.domError.type}", e.errorMessage?.toString(), null)
            } catch (e: GetCredentialException) {
                result.error("get_credential_failed_${e.type}", e.errorMessage?.toString(), null)
            } catch (e: Exception) {
                result.error("unexpected_error", e.message, null)
            }
        }
    }

    // --- WebAuthn JSON option builders --------------------------------------
    // These are the *ClientRequestOptions JSON shapes androidx.credentials'
    // CreatePublicKeyCredentialRequest/GetPublicKeyCredentialOption take as
    // requestJson -- WebAuthn L2/L3's PublicKeyCredentialCreationOptionsJSON /
    // PublicKeyCredentialRequestOptionsJSON, not a bespoke format.

    private fun buildCreateRequestJson(
        challenge: String, rpId: String, userId: String, userName: String,
    ): String {
        // WebAuthn's user.id is an opaque byte handle, base64url-encoded in the
        // JSON form. Never read back by this server (c.principal.userId from the
        // session is what's actually trusted -- see server/routes.mjs's
        // register/verify) -- only used by the platform authenticator itself to
        // key its resident-credential storage.
        val userIdB64 = Base64.encodeToString(
            userId.toByteArray(Charsets.UTF_8),
            Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
        return JSONObject().apply {
            put("challenge", challenge)
            put("rp", JSONObject().apply {
                put("id", rpId)
                put("name", "Olive Branch")
            })
            put("user", JSONObject().apply {
                put("id", userIdB64)
                put("name", userName)
                put("displayName", userName)
            })
            put("pubKeyCredParams", JSONArray().put(JSONObject().apply {
                put("type", "public-key")
                // ES256 -- the only alg packages/auth/src/attestation.ts's
                // extractCredentialPublicKey() accepts (COSE_ALG_ES256 = -7).
                put("alg", -7)
            }))
            put("timeout", 60000)
            put("attestation", "none")
            put("authenticatorSelection", JSONObject().apply {
                put("authenticatorAttachment", "platform")
                // Required, not merely preferred -- see file header: login has
                // no allowCredentials list, so only a discoverable credential
                // can ever be found again by authenticate() below.
                put("residentKey", "required")
                put("requireResidentKey", true)
                put("userVerification", "required")
            })
        }.toString()
    }

    private fun buildGetOptionJson(challenge: String, rpId: String): String =
        JSONObject().apply {
            put("challenge", challenge)
            put("rpId", rpId)
            put("userVerification", "required")
            put("timeout", 60000)
        }.toString()
}
