// CORS para las Edge Functions.
//
// SIN ESTO, NINGUNA FUNCIÓN ES LLAMABLE DESDE EL NAVEGADOR — y el síntoma no lo
// dice. Un `fetch` con cabeceras `authorization` y `content-type` no es una
// petición simple: el navegador manda antes un **preflight** `OPTIONS`
// preguntando si puede hacer el POST. Si esa pregunta no se contesta con las
// cabeceras adecuadas, el POST no llega a salir.
//
// Costó una tarde encontrarlo porque desde `curl` todo funcionaba: curl no hace
// preflight. Las funciones estaban perfectas, se probaron de punta a punta por
// HTTP y respondían 200. Desde la aplicación, en cambio, la petición moría antes
// de existir. Se veía como «el QR no carga» y «el pago no avanza», dos síntomas
// que no se parecen entre sí y tienen la misma causa.
//
// > Verificar por HTTP no es verificar desde el navegador. Son dos clientes
// > distintos, y solo uno tiene política de mismo origen.
//
// `*` en el origen es correcto aquí y conviene entender por qué no es un
// descuido: lo que autoriza estas funciones es el JWT del `Authorization`, no el
// dominio desde el que se pide. Un origen permisivo no da acceso a nada — quien
// no tenga sesión válida sigue recibiendo 401. Restringirlo a un dominio fijo
// obligaría además a redesplegar cada vez que cambie la URL del front.

export const CORS = {
  'access-control-allow-origin': '*',
  // `apikey` y `x-client-info` los añade supabase-js por su cuenta. Si no están
  // en esta lista, el preflight los rechaza aunque el resto esté bien.
  'access-control-allow-headers':
    'authorization, apikey, content-type, x-client-info, x-supabase-api-version',
  'access-control-allow-methods': 'POST, OPTIONS',
  // Cachea el preflight una hora: sin esto el navegador pregunta antes de CADA
  // petición, y la wallet pide un token nuevo cada 30 segundos.
  'access-control-max-age': '3600',
} as const;

/** La respuesta al preflight. Va SIEMPRE la primera, antes de cualquier otra cosa. */
export function preflight(req: Request): Response | null {
  return req.method === 'OPTIONS' ? new Response(null, { status: 204, headers: CORS }) : null;
}

/**
 * Respuesta JSON con CORS.
 *
 * Las cabeceras van también en los errores, y eso importa: sin ellas el
 * navegador no puede leer el cuerpo de un 403 o un 409, así que el mensaje
 * cuidadosamente escrito —«el QR estará disponible el 19 de octubre»— se
 * convierte en un error de red genérico.
 */
export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'content-type': 'application/json', 'cache-control': 'no-store' },
  });
}
