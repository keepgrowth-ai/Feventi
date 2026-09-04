// El QR rotativo del ticket. Art. 2.
//
// UNA sola definición del algoritmo, importada por las dos mitades:
// `qr-token` lo emite y `qr-validate` lo verifica. Tenerlo dos veces sería
// garantizar que un día alguien arregla un lado y no el otro — y el síntoma
// sería que los QR dejan de escanear en la puerta, de noche, con cola.
//
//   slot  = floor(unix_seconds / 30)
//   mac   = hmac_sha256(secreto_del_ticket, `${ticket_id}:${slot}`)
//   token = base64url( ticket_id(16) | slot(6, big-endian) | mac[0..15] )
//
// El MAC se trunca a 16 bytes: 128 bits sobran contra falsificación y mantienen
// el QR pequeño, que es lo que hace que se lea rápido con poca luz.
//
// El slot viaja EN CLARO, a propósito. No es un secreto, y permite al validador
// distinguir «MAC inválida» —el código no es de Feventi— de «MAC válida pero
// vieja», que solo puede venir de una captura de pantalla. Sin esa distinción
// los dos casos darían «QR inválido» y se perdería la señal antifraude más
// valiosa de la noche.

/** Ventana de rotación, en segundos. 30, como el mockup. */
export const SLOT_SECONDS = 30;

/**
 * Tolerancia, en slots, al comparar el token presentado con el actual.
 *
 * ±1 y no 0 porque el reloj del móvil del fan y el del servidor no coinciden:
 * con tolerancia cero, un desfase de dos segundos en el borde del slot rechaza
 * a alguien con una entrada legítima. El coste es que la ventana de replay pasa
 * de 30 a 90 s, y el replay ya está contenido por el uso único del ticket.
 */
export const SLOT_TOLERANCE = 1;

export function currentSlot(nowMs = Date.now()): number {
  return Math.floor(nowMs / 1000 / SLOT_SECONDS);
}

export function b64url(bytes: Uint8Array): string {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export function fromB64url(s: string): Uint8Array {
  const b64 = s.replace(/-/g, '+').replace(/_/g, '/');
  const bin = atob(b64 + '='.repeat((4 - (b64.length % 4)) % 4));
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/** uuid con guiones → 16 bytes. */
export function uuidBytes(uuid: string): Uint8Array {
  const hex = uuid.replace(/-/g, '');
  const out = new Uint8Array(16);
  for (let i = 0; i < 16; i++) out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  return out;
}

/** 16 bytes → uuid con guiones. */
export function bytesToUuid(b: Uint8Array): string {
  const h = [...b].map((x) => x.toString(16).padStart(2, '0')).join('');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

/** El bytea que devuelve PostgREST viene como `\x…` hexadecimal. */
export function byteaToBytes(v: unknown): Uint8Array {
  const hex = String(v).replace(/^\\x/, '');
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  return out;
}

export async function hmac(secret: Uint8Array, msg: string): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    'raw',
    secret as unknown as BufferSource,
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  return new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(msg)));
}

export async function buildToken(
  ticketId: string,
  slot: number,
  secret: Uint8Array,
): Promise<string> {
  const mac = await hmac(secret, `${ticketId}:${slot}`);
  const out = new Uint8Array(38);
  out.set(uuidBytes(ticketId), 0);
  // 6 bytes de slot: con ventanas de 30 s alcanza para ~6.7 mil millones de años.
  for (let i = 0; i < 6; i++) out[16 + i] = (slot / 2 ** (8 * (5 - i))) & 0xff;
  out.set(mac.slice(0, 16), 22);
  return b64url(out);
}

/** Lo que se puede leer del token SIN el secreto: quién dice ser y de cuándo. */
export function parseToken(token: string): { ticketId: string; slot: number; mac: Uint8Array } | null {
  try {
    const raw = fromB64url(token);
    if (raw.length !== 38) return null;
    let slot = 0;
    for (let i = 0; i < 6; i++) slot = slot * 256 + raw[16 + i];
    return { ticketId: bytesToUuid(raw.slice(0, 16)), slot, mac: raw.slice(22, 38) };
  } catch {
    return null;
  }
}

/** Comparación en tiempo constante. */
export function timingSafeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

/**
 * ¿La MAC de este token es la que corresponde a su propio slot?
 *
 * Se recalcula sobre el slot QUE VIENE EN EL TOKEN, no sobre el actual. Así una
 * MAC vieja sigue siendo válida y el validador puede decir «esto es una captura
 * de hace diez minutos» en vez de «código inválido». Lo de si el slot está
 * dentro de la ventana lo decide `gate_checkin`, con `slot_delta`.
 */
export async function macMatches(
  parsed: { ticketId: string; slot: number; mac: Uint8Array },
  secret: Uint8Array,
): Promise<boolean> {
  const expected = (await hmac(secret, `${parsed.ticketId}:${parsed.slot}`)).slice(0, 16);
  return timingSafeEqual(parsed.mac, expected);
}
