// OLIVE BRANCH — magic-byte media sniffing for POST .../media (audit S-B8).
//
// The upload route used to accept ANY bytes and the media route served every
// blob as application/octet-stream. A child's message is a photo, a short
// video or a voice note, so the accepted set is exactly those containers, and
// the MIME recorded in the media_upload ledger is the one the BYTES prove, never
// one the client claims. Anything else is refused with 415.
//
//   JPEG  FF D8 FF
//   PNG   89 50 4E 47 0D 0A 1A 0A
//   WebM  1A 45 DF A3                      (Matroska/EBML header)
//   MP4   ....ftyp<brand>                  video/mp4, or audio/mp4 for an M4A brand

const FTYP_AUDIO_BRANDS = new Set(['M4A ', 'M4B ', 'M4P ']);

/** @returns {{ mime: string } | null} */
export function sniffMedia(bytes) {
  const b = Buffer.isBuffer(bytes) ? bytes : Buffer.from(bytes);
  if (b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return { mime: 'image/jpeg' };
  if (b.length >= 8 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47 &&
      b[4] === 0x0d && b[5] === 0x0a && b[6] === 0x1a && b[7] === 0x0a) return { mime: 'image/png' };
  if (b.length >= 4 && b[0] === 0x1a && b[1] === 0x45 && b[2] === 0xdf && b[3] === 0xa3) {
    return { mime: 'video/webm' };
  }
  if (b.length >= 12 && b.toString('latin1', 4, 8) === 'ftyp') {
    return { mime: FTYP_AUDIO_BRANDS.has(b.toString('latin1', 8, 12)) ? 'audio/mp4' : 'video/mp4' };
  }
  return null;
}

/** Every MIME sniffMedia() can return — the only values the ledger / serve route may carry. */
export const SERVABLE_MIMES = new Set(['image/jpeg', 'image/png', 'video/webm', 'video/mp4', 'audio/mp4']);
