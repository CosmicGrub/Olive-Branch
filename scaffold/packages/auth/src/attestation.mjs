import { createPublicKey } from "node:crypto";
function fail(msg) {
  throw new Error(`CBOR: ${msg}`);
}
function decodeItem(buf, offset) {
  if (offset >= buf.length) fail("unexpected end of buffer reading initial byte");
  const initial = buf[offset];
  const majorType = initial >> 5;
  const additionalInfo = initial & 31;
  let argument;
  let headerLen;
  if (additionalInfo <= 23) {
    argument = additionalInfo;
    headerLen = 1;
  } else if (additionalInfo === 24) {
    if (offset + 2 > buf.length) fail("truncated 1-byte length");
    argument = buf.readUInt8(offset + 1);
    headerLen = 2;
  } else if (additionalInfo === 25) {
    if (offset + 3 > buf.length) fail("truncated 2-byte length");
    argument = buf.readUInt16BE(offset + 1);
    headerLen = 3;
  } else if (additionalInfo === 26) {
    if (offset + 5 > buf.length) fail("truncated 4-byte length");
    argument = buf.readUInt32BE(offset + 1);
    headerLen = 5;
  } else if (additionalInfo === 27) {
    if (offset + 9 > buf.length) fail("truncated 8-byte length");
    const big = buf.readBigUInt64BE(offset + 1);
    if (big > BigInt(Number.MAX_SAFE_INTEGER)) fail("8-byte length exceeds safe integer range");
    argument = Number(big);
    headerLen = 9;
  } else if (additionalInfo === 31) {
    fail("indefinite-length items are not supported (no real authenticator emits them)");
  } else {
    fail(`reserved additional-info value ${additionalInfo}`);
  }
  const start = offset + headerLen;
  switch (majorType) {
    case 0:
      return { value: argument, bytesConsumed: headerLen };
    case 1:
      return { value: -1 - argument, bytesConsumed: headerLen };
    case 2: {
      if (start + argument > buf.length) fail("truncated byte string");
      return { value: buf.subarray(start, start + argument), bytesConsumed: headerLen + argument };
    }
    case 3: {
      if (start + argument > buf.length) fail("truncated text string");
      return {
        value: buf.subarray(start, start + argument).toString("utf8"),
        bytesConsumed: headerLen + argument
      };
    }
    case 4: {
      const arr = [];
      let pos = start;
      for (let i = 0; i < argument; i++) {
        const item = decodeItem(buf, pos);
        arr.push(item.value);
        pos += item.bytesConsumed;
      }
      return { value: arr, bytesConsumed: pos - offset };
    }
    case 5: {
      const map = /* @__PURE__ */ new Map();
      let pos = start;
      for (let i = 0; i < argument; i++) {
        const key = decodeItem(buf, pos);
        pos += key.bytesConsumed;
        const val = decodeItem(buf, pos);
        pos += val.bytesConsumed;
        map.set(key.value, val.value);
      }
      return { value: map, bytesConsumed: pos - offset };
    }
    case 6: {
      const inner = decodeItem(buf, start);
      return { value: inner.value, bytesConsumed: headerLen + inner.bytesConsumed };
    }
    case 7:
      if (additionalInfo === 20) return { value: false, bytesConsumed: headerLen };
      if (additionalInfo === 21) return { value: true, bytesConsumed: headerLen };
      if (additionalInfo === 22) return { value: null, bytesConsumed: headerLen };
      if (additionalInfo === 23) return { value: void 0, bytesConsumed: headerLen };
      fail(`unsupported major-type-7 simple/float value (additionalInfo=${additionalInfo})`);
    default:
      fail(`impossible major type ${majorType}`);
  }
}
function parseAttestationObject(attestationObjectB64u) {
  let buf;
  try {
    buf = Buffer.from(attestationObjectB64u, "base64url");
  } catch {
    throw new Error("attestationObject: not valid base64url");
  }
  if (buf.length === 0) throw new Error("attestationObject: empty");
  let decoded;
  try {
    decoded = decodeItem(buf, 0);
  } catch (e) {
    throw new Error(`attestationObject: malformed CBOR \u2014 ${e.message}`);
  }
  const top = decoded.value;
  if (!(top instanceof Map)) {
    throw new Error("attestationObject: top-level CBOR value is not a map");
  }
  if (!top.has("fmt")) throw new Error("attestationObject: missing fmt");
  if (!top.has("attStmt")) throw new Error("attestationObject: missing attStmt");
  if (!top.has("authData")) throw new Error("attestationObject: missing authData");
  const fmt = top.get("fmt");
  const authData = top.get("authData");
  if (typeof fmt !== "string") throw new Error("attestationObject: fmt is not a text string");
  if (!Buffer.isBuffer(authData)) throw new Error("attestationObject: authData is not a byte string");
  return { fmt, authData };
}
const ATTESTED_CREDENTIAL_DATA_FLAG = 64;
const AUTH_DATA_FIXED_PREFIX_LEN = 32 + 1 + 4;
function extractCredentialPublicKey(authData) {
  if (authData.length < AUTH_DATA_FIXED_PREFIX_LEN) {
    throw new Error("authData: shorter than the fixed 37-byte prefix");
  }
  const flags = authData[32];
  if ((flags & ATTESTED_CREDENTIAL_DATA_FLAG) === 0) {
    throw new Error(
      "authData: attested credential data flag (0x40) is not set \u2014 this is a login authData (or a malformed registration one), not a registration one"
    );
  }
  let offset = AUTH_DATA_FIXED_PREFIX_LEN;
  const AAGUID_LEN = 16;
  const CRED_ID_LEN_FIELD = 2;
  if (authData.length < offset + AAGUID_LEN + CRED_ID_LEN_FIELD) {
    throw new Error("authData: truncated before aaguid/credentialIdLength");
  }
  offset += AAGUID_LEN;
  const credIdLen = authData.readUInt16BE(offset);
  offset += CRED_ID_LEN_FIELD;
  if (authData.length < offset + credIdLen) {
    throw new Error("authData: truncated credentialId");
  }
  const credentialIdBuf = authData.subarray(offset, offset + credIdLen);
  offset += credIdLen;
  if (offset >= authData.length) {
    throw new Error("authData: no COSE_Key bytes follow the credentialId");
  }
  let decoded;
  try {
    decoded = decodeItem(authData, offset);
  } catch (e) {
    throw new Error(`authData: malformed COSE_Key CBOR \u2014 ${e.message}`);
  }
  const cose = decoded.value;
  if (!(cose instanceof Map)) throw new Error("authData: COSE_Key is not a CBOR map");
  const kty = cose.get(1);
  const alg = cose.get(3);
  const crv = cose.get(-1);
  const x = cose.get(-2);
  const y = cose.get(-3);
  const COSE_KTY_EC2 = 2;
  const COSE_ALG_ES256 = -7;
  const COSE_CRV_P256 = 1;
  if (kty !== COSE_KTY_EC2) {
    throw new Error(`COSE_Key: unsupported kty ${String(kty)} (only EC2/2 is supported)`);
  }
  if (alg !== COSE_ALG_ES256) {
    throw new Error(`COSE_Key: unsupported alg ${String(alg)} (only ES256/-7 is supported)`);
  }
  if (crv !== COSE_CRV_P256) {
    throw new Error(`COSE_Key: unsupported crv ${String(crv)} (only P-256/1 is supported)`);
  }
  if (!Buffer.isBuffer(x) || x.length !== 32) {
    throw new Error("COSE_Key: x is not a 32-byte P-256 coordinate");
  }
  if (!Buffer.isBuffer(y) || y.length !== 32) {
    throw new Error("COSE_Key: y is not a 32-byte P-256 coordinate");
  }
  const publicKey = createPublicKey({
    key: { kty: "EC", crv: "P-256", x: x.toString("base64url"), y: y.toString("base64url") },
    format: "jwk"
  });
  const publicKeyPem = publicKey.export({ type: "spki", format: "pem" }).toString();
  return { credentialId: credentialIdBuf.toString("base64url"), publicKeyPem };
}
export {
  extractCredentialPublicKey,
  parseAttestationObject
};
