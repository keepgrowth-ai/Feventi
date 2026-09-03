/**
 * Dinero. Art. 5.
 *
 * El front FORMATEA, no calcula. Todo importe llega del servidor en céntimos
 * enteros y aquí solo se le pone la coma y el `S/ `. Ninguna operación
 * aritmética de dinero vive en el cliente: si un total hay que sumarlo, lo suma
 * la base de datos, que es la que tiene la verdad.
 */

const FORMAT = new Intl.NumberFormat('es-PE', {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

/** 12345 → "S/ 123.45" */
export function soles(cents: number | null | undefined): string {
  if (cents == null) return '—';
  return `S/ ${FORMAT.format(cents / 100)}`;
}

/** Para líneas de descuento y comisión: 3600 → "− S/ 36.00" */
export function negative(cents: number | null | undefined): string {
  if (cents == null) return '—';
  return `− ${soles(Math.abs(cents))}`;
}

/** 600 → "6%". Los bps evitan decimales perdidos en el camino. */
export function bpsToPercent(bps: number): string {
  return `${bps / 100}%`;
}

/**
 * Una línea del desglose de precio. `value_cents` viene del servidor.
 * El desglose tiene que sumar EXACTO al total (004, AC-18): el redondeo del
 * cargo se hace una vez sobre el subtotal, en la base, no por línea aquí.
 */
export interface PriceLine {
  readonly label: string;
  readonly valueCents: number;
  readonly kind: 'base' | 'discount' | 'charge' | 'total';
}
