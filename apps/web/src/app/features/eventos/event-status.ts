import type { ChipTone } from '../../shared/ui/chip';
import type { Enums } from '../../core/db.types';

export type EventStatus = Enums<'event_status'>;

/**
 * El copy de cada estado, en un solo sitio. Cuatro pantallas lo consumen y
 * tienen que decir exactamente lo mismo.
 *
 * Los textos no son decorativos, salen del spec:
 *
 * - `approved`/`setup` no es `published`. Feventi autoriza; el organizador
 *   decide cuándo abre la venta. La UI lo dice y nombra el paso que falta.
 * - `paused` NO es cancelado. «Las entradas ya emitidas siguen siendo válidas»
 *   es la diferencia entre un fan tranquilo y un caso de soporte.
 * - En `draft` la acción se llama «Enviar a revisión», nunca «Publicar».
 */
export interface StatusCopy {
  readonly label: string;
  readonly tone: ChipTone;
  /** Qué significa, para el organizador. */
  readonly meaning: string;
  /** El siguiente paso, y de quién es. Null si no hay nada que hacer. */
  readonly nextStep: string | null;
  /** ¿Vende entradas ahora? Solo `published`. Art. 4. */
  readonly selling: boolean;
}

export const EVENT_STATUS: Record<EventStatus, StatusCopy> = {
  draft: {
    label: 'Borrador',
    tone: 'neutral',
    meaning: 'Solo lo ves tú. No vende entradas y no lo ha visto Feventi.',
    nextStep: 'Completa la ficha y envíala a revisión.',
    selling: false,
  },
  pending_review: {
    label: 'En revisión',
    tone: 'warn',
    meaning: 'Feventi está revisando tu solicitud. Todavía no vende entradas.',
    nextStep: 'Nada por tu parte. Te avisamos aquí cuando haya respuesta.',
    selling: false,
  },
  changes_requested: {
    label: 'Requiere info',
    tone: 'danger',
    meaning: 'Feventi necesita algo más antes de aprobar.',
    nextStep: 'Revisa la observación, corrige y vuelve a enviar.',
    selling: false,
  },
  rejected: {
    label: 'Rechazada',
    tone: 'danger',
    meaning: 'Feventi no aprobó esta solicitud.',
    nextStep: 'Lee el motivo. Si crees que hay un error, abre un caso de soporte.',
    selling: false,
  },
  approved: {
    label: 'Aprobado',
    tone: 'info',
    meaning: 'Feventi autorizó el evento. Aprobado no es publicado: aún no vende.',
    nextStep: 'Carga zonas, entradas y precios.',
    selling: false,
  },
  setup: {
    label: 'En configuración',
    tone: 'info',
    meaning: 'Aprobado y listo para cargar inventario. Todavía no vende.',
    nextStep: 'Termina zonas y precios, y publica cuando quieras abrir la venta. La decisión es tuya.',
    selling: false,
  },
  published: {
    label: 'Publicado',
    tone: 'success',
    meaning: 'El evento está a la venta y visible en el catálogo.',
    nextStep: null,
    selling: true,
  },
  paused: {
    label: 'Venta pausada',
    tone: 'warn',
    meaning:
      'La venta está detenida y el evento salió del catálogo. Las entradas ya emitidas siguen siendo válidas y su QR funciona en puerta.',
    nextStep: 'Contacta a Feventi para reanudar la venta.',
    selling: false,
  },
  cancelled: {
    label: 'Cancelado',
    tone: 'danger',
    meaning: 'El evento no se realizará y las entradas quedan sin validez.',
    nextStep: 'El proceso de devoluciones lo coordina Feventi.',
    selling: false,
  },
  finished: {
    label: 'Finalizado',
    tone: 'neutral',
    meaning: 'El evento ya ocurrió.',
    nextStep: null,
    selling: false,
  },
};

/** Los estados que la pantalla «Solicitudes» agrupa, en el orden en que importan. */
export const REQUEST_STATUSES: readonly EventStatus[] = [
  'changes_requested',
  'pending_review',
  'draft',
  'rejected',
] as const;

export const CHECKLIST_LABELS: Record<string, string> = {
  datos_generales: 'Datos generales',
  organizador_ruc: 'Organizador y RUC',
  venue_plano: 'Venue / plano',
  fechas_funciones: 'Fechas y funciones',
  zonas_fases: 'Zonas y fases de precio',
  cortesias_bolsas: 'Cortesías y bolsas',
};

export const CHECKLIST_TONE: Record<string, ChipTone> = {
  ok: 'success',
  pending: 'warn',
  na: 'neutral',
};

export const CHECKLIST_STATE_LABEL: Record<string, string> = {
  ok: 'Listo',
  pending: 'Pendiente',
  na: 'No aplica',
};
