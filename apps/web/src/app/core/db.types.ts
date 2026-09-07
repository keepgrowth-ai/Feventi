/**
 * GENERADO — no editar a mano (Art. 12.3).
 *   npm run gen:types
 *
 * El schema es la fuente de verdad de los tipos. Si algo aquí no cuadra con el
 * código, lo que está mal es el código o falta regenerar, nunca este archivo.
 *
 * Nota: `private` no aparece porque PostgREST no lo expone (migración 0010), y
 * `profile_identity` aparece en los tipos pero es inalcanzable en tiempo de
 * ejecución: RLS activa, cero políticas, sin grants (Art. 7.1).
 */

export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

/** Los seis ítems del checklist de revisión (007). Forma garantizada por un CHECK. */
export type ReviewChecklist = Record<
  | 'datos_generales'
  | 'organizador_ruc'
  | 'venue_plano'
  | 'fechas_funciones'
  | 'zonas_fases'
  | 'cortesias_bolsas',
  'ok' | 'pending' | 'na'
>;

/** Un tramo de la política de liquidación declarada (007). Fase 2 lo hace real. */
export interface PayoutTranche {
  readonly pct: number;
  readonly trigger: string;
}

export type Database = {
  __InternalSupabase: { PostgrestVersion: '14.5' };
  public: {
    Tables: {
      profiles: {
        Row: {
          id: string;
          full_name: string | null;
          email: string | null;
          phone: string | null;
          dni_last4: string | null;
          dni_verified_at: string | null;
          ninja_mode: boolean;
          avatar_url: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id: string;
          full_name?: string | null;
          email?: string | null;
          phone?: string | null;
          dni_last4?: string | null;
          dni_verified_at?: string | null;
          ninja_mode?: boolean;
          avatar_url?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Update: {
          id?: string;
          full_name?: string | null;
          email?: string | null;
          phone?: string | null;
          dni_last4?: string | null;
          dni_verified_at?: string | null;
          ninja_mode?: boolean;
          avatar_url?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Relationships: [];
      };
      profile_identity: {
        Row: { user_id: string; dni_hash: string; created_at: string; updated_at: string };
        Insert: { user_id: string; dni_hash: string; created_at?: string; updated_at?: string };
        Update: { user_id?: string; dni_hash?: string; created_at?: string; updated_at?: string };
        Relationships: [
          {
            foreignKeyName: 'profile_identity_user_id_fkey';
            columns: ['user_id'];
            isOneToOne: true;
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
        ];
      };
      user_roles: {
        Row: { user_id: string; role: Database['public']['Enums']['app_role']; created_at: string };
        Insert: {
          user_id: string;
          role: Database['public']['Enums']['app_role'];
          created_at?: string;
        };
        Update: {
          user_id?: string;
          role?: Database['public']['Enums']['app_role'];
          created_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'user_roles_user_id_fkey';
            columns: ['user_id'];
            isOneToOne: false;
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
        ];
      };
      organizers: {
        Row: {
          id: string;
          legal_name: string;
          trade_name: string | null;
          ruc: string | null;
          status: Database['public']['Enums']['organizer_status'];
          contact_email: string | null;
          contact_phone: string | null;
          reputation: number | null;
          created_by: string | null;
          approved_at: string | null;
          approved_by: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          legal_name: string;
          trade_name?: string | null;
          ruc?: string | null;
          status?: Database['public']['Enums']['organizer_status'];
          contact_email?: string | null;
          contact_phone?: string | null;
          reputation?: number | null;
          created_by?: string | null;
          approved_at?: string | null;
          approved_by?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Update: {
          id?: string;
          legal_name?: string;
          trade_name?: string | null;
          ruc?: string | null;
          status?: Database['public']['Enums']['organizer_status'];
          contact_email?: string | null;
          contact_phone?: string | null;
          reputation?: number | null;
          created_by?: string | null;
          approved_at?: string | null;
          approved_by?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'organizers_approved_by_fkey';
            columns: ['approved_by'];
            isOneToOne: false;
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'organizers_created_by_fkey';
            columns: ['created_by'];
            isOneToOne: false;
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
        ];
      };
      organizer_members: {
        Row: {
          organizer_id: string;
          user_id: string;
          role: Database['public']['Enums']['organizer_role'];
          invited_by: string | null;
          revoked_at: string | null;
          created_at: string;
        };
        Insert: {
          organizer_id: string;
          user_id: string;
          role?: Database['public']['Enums']['organizer_role'];
          invited_by?: string | null;
          revoked_at?: string | null;
          created_at?: string;
        };
        Update: {
          organizer_id?: string;
          user_id?: string;
          role?: Database['public']['Enums']['organizer_role'];
          invited_by?: string | null;
          revoked_at?: string | null;
          created_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'organizer_members_organizer_id_fkey';
            columns: ['organizer_id'];
            isOneToOne: false;
            referencedRelation: 'organizers';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'organizer_members_user_id_fkey';
            columns: ['user_id'];
            isOneToOne: false;
            referencedRelation: 'profiles';
            referencedColumns: ['id'];
          },
        ];
      };
      venues: {
        Row: {
          id: string;
          name: string;
          city: string;
          address: string | null;
          capacity: number | null;
          created_by: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          name: string;
          city: string;
          address?: string | null;
          capacity?: number | null;
          created_by?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Update: {
          id?: string;
          name?: string;
          city?: string;
          address?: string | null;
          capacity?: number | null;
          created_by?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Relationships: [];
      };
      events: {
        Row: {
          id: string;
          code: string;
          organizer_id: string;
          venue_id: string | null;
          slug: string | null;
          title: string | null;
          description: string | null;
          category: string | null;
          hero_image_url: string | null;
          starts_at: string | null;
          doors_at: string | null;
          timezone: string;
          status: Database['public']['Enums']['event_status'];
          visibility: Database['public']['Enums']['event_visibility'];
          capacity: number | null;
          max_per_user: number;
          resale_enabled: boolean;
          max_resales: number;
          resale_commission_bps: number;
          service_charge_bps: number;
          service_charge_payer: Database['public']['Enums']['charge_payer'];
          qr_lead_days: number;
          nomination_mode: Database['public']['Enums']['nomination_mode'];
          payout_policy: Json;
          review_checklist: Json;
          featured_at: string | null;
          submitted_at: string | null;
          approved_at: string | null;
          published_at: string | null;
          paused_at: string | null;
          cancelled_at: string | null;
          created_by: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          code?: string;
          organizer_id: string;
          venue_id?: string | null;
          slug?: string | null;
          title?: string | null;
          description?: string | null;
          category?: string | null;
          hero_image_url?: string | null;
          starts_at?: string | null;
          doors_at?: string | null;
          timezone?: string;
          status?: Database['public']['Enums']['event_status'];
          visibility?: Database['public']['Enums']['event_visibility'];
          capacity?: number | null;
          max_per_user?: number;
          resale_enabled?: boolean;
          max_resales?: number;
          resale_commission_bps?: number;
          service_charge_bps?: number;
          service_charge_payer?: Database['public']['Enums']['charge_payer'];
          qr_lead_days?: number;
          nomination_mode?: Database['public']['Enums']['nomination_mode'];
          payout_policy?: Json;
          review_checklist?: Json;
          featured_at?: string | null;
          submitted_at?: string | null;
          approved_at?: string | null;
          published_at?: string | null;
          paused_at?: string | null;
          cancelled_at?: string | null;
          created_by?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database['public']['Tables']['events']['Insert']>;
        Relationships: [
          {
            foreignKeyName: 'events_organizer_id_fkey';
            columns: ['organizer_id'];
            isOneToOne: false;
            referencedRelation: 'organizers';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'events_venue_id_fkey';
            columns: ['venue_id'];
            isOneToOne: false;
            referencedRelation: 'venues';
            referencedColumns: ['id'];
          },
        ];
      };
      event_review_notes: {
        Row: {
          id: string;
          event_id: string;
          actor_id: string | null;
          action: Database['public']['Enums']['review_action'];
          note: string | null;
          checklist_snapshot: Json | null;
          status_before: Database['public']['Enums']['event_status'] | null;
          status_after: Database['public']['Enums']['event_status'] | null;
          internal: boolean;
          created_at: string;
        };
        Insert: {
          id?: string;
          event_id: string;
          actor_id?: string | null;
          action: Database['public']['Enums']['review_action'];
          note?: string | null;
          checklist_snapshot?: Json | null;
          status_before?: Database['public']['Enums']['event_status'] | null;
          status_after?: Database['public']['Enums']['event_status'] | null;
          internal?: boolean;
          created_at?: string;
        };
        Update: Partial<Database['public']['Tables']['event_review_notes']['Insert']>;
        Relationships: [
          {
            foreignKeyName: 'event_review_notes_event_id_fkey';
            columns: ['event_id'];
            isOneToOne: false;
            referencedRelation: 'events';
            referencedColumns: ['id'];
          },
        ];
      };
      zones: {
        Row: {
          id: string;
          event_id: string;
          name: string;
          kind: Database['public']['Enums']['zone_kind'];
          numbered: boolean;
          capacity: number;
          notes: string | null;
          sort_order: number;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          event_id: string;
          name: string;
          kind: Database['public']['Enums']['zone_kind'];
          numbered?: boolean;
          capacity: number;
          notes?: string | null;
          sort_order?: number;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database['public']['Tables']['zones']['Insert']>;
        Relationships: [
          {
            foreignKeyName: 'zones_event_id_fkey';
            columns: ['event_id'];
            isOneToOne: false;
            referencedRelation: 'events';
            referencedColumns: ['id'];
          },
        ];
      };
      zone_segments: {
        Row: {
          id: string;
          zone_id: string;
          /** Siempre 'seated'. Existe para la FK compuesta contra zones(id, kind). */
          zone_kind: Database['public']['Enums']['zone_kind'];
          label: string;
          row_from: string | null;
          row_to: string | null;
          sort_order: number;
          created_at: string;
        };
        Insert: {
          id?: string;
          zone_id: string;
          zone_kind?: Database['public']['Enums']['zone_kind'];
          label: string;
          row_from?: string | null;
          row_to?: string | null;
          sort_order?: number;
          created_at?: string;
        };
        Update: Partial<Database['public']['Tables']['zone_segments']['Insert']>;
        Relationships: [
          {
            foreignKeyName: 'zone_segments_zone_id_fkey';
            columns: ['zone_id'];
            isOneToOne: false;
            referencedRelation: 'zones';
            referencedColumns: ['id'];
          },
        ];
      };
      price_phases: {
        Row: {
          id: string;
          event_id: string;
          name: string;
          kind: Database['public']['Enums']['phase_kind'];
          starts_at: string;
          ends_at: string;
          sort_order: number;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          event_id: string;
          name: string;
          kind?: Database['public']['Enums']['phase_kind'];
          starts_at: string;
          ends_at: string;
          sort_order?: number;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database['public']['Tables']['price_phases']['Insert']>;
        Relationships: [
          {
            foreignKeyName: 'price_phases_event_id_fkey';
            columns: ['event_id'];
            isOneToOne: false;
            referencedRelation: 'events';
            referencedColumns: ['id'];
          },
        ];
      };
      price_tiers: {
        Row: {
          id: string;
          event_id: string;
          zone_id: string;
          segment_id: string | null;
          phase_id: string;
          price_cents: number;
          currency: string;
          stock: number;
          /** Los mueve 004 en funciones transaccionales; el cliente los tiene revocados. */
          reserved: number;
          sold: number;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          event_id: string;
          zone_id: string;
          segment_id?: string | null;
          phase_id: string;
          price_cents: number;
          currency?: string;
          stock: number;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database['public']['Tables']['price_tiers']['Insert']>;
        Relationships: [
          {
            foreignKeyName: 'price_tiers_zone_id_fkey';
            columns: ['zone_id'];
            isOneToOne: false;
            referencedRelation: 'zones';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'price_tiers_phase_id_fkey';
            columns: ['phase_id'];
            isOneToOne: false;
            referencedRelation: 'price_phases';
            referencedColumns: ['id'];
          },
        ];
      };
      seats: {
        Row: {
          id: string;
          zone_id: string;
          zone_kind: Database['public']['Enums']['zone_kind'];
          segment_id: string | null;
          row_label: string;
          seat_number: number;
          /** Decisión operativa del organizador, no reflejo de la venta. */
          blocked: boolean;
          block_reason: string | null;
          created_at: string;
        };
        Insert: {
          id?: string;
          zone_id: string;
          zone_kind?: Database['public']['Enums']['zone_kind'];
          segment_id?: string | null;
          row_label: string;
          seat_number: number;
          blocked?: boolean;
          block_reason?: string | null;
          created_at?: string;
        };
        Update: Partial<Database['public']['Tables']['seats']['Insert']>;
        Relationships: [
          {
            foreignKeyName: 'seats_zone_id_fkey';
            columns: ['zone_id'];
            isOneToOne: false;
            referencedRelation: 'zones';
            referencedColumns: ['id'];
          },
        ];
      };
      orders: {
        Row: {
          id: string;
          code: string;
          event_id: string;
          buyer_id: string;
          status: Database['public']['Enums']['order_status'];
          subtotal_cents: number;
          discount_cents: number;
          service_charge_cents: number;
          total_cents: number;
          currency: string;
          service_charge_payer: Database['public']['Enums']['charge_payer'];
          service_charge_bps: number;
          promo_code: string | null;
          reserved_until: string | null;
          created_at: string;
          paid_at: string | null;
          failed_at: string | null;
          expired_at: string | null;
        };
        /** Nadie inserta órdenes desde el cliente: solo `reserve_order`. */
        Insert: never;
        Update: never;
        Relationships: [
          {
            foreignKeyName: 'orders_event_id_fkey';
            columns: ['event_id'];
            isOneToOne: false;
            referencedRelation: 'events';
            referencedColumns: ['id'];
          },
        ];
      };
      order_items: {
        Row: {
          id: string;
          order_id: string;
          price_tier_id: string;
          seat_id: string | null;
          unit_price_cents: number;
          attendee_name: string | null;
          /** Art. 7.1: solo lo escribe `set_item_attendee`, hasheado en el servidor. */
          attendee_dni_hash: string | null;
          attendee_dni_last4: string | null;
          nominated_at: string | null;
          created_at: string;
        };
        Insert: never;
        Update: never;
        Relationships: [
          {
            foreignKeyName: 'order_items_order_id_fkey';
            columns: ['order_id'];
            isOneToOne: false;
            referencedRelation: 'orders';
            referencedColumns: ['id'];
          },
        ];
      };
      payments: {
        Row: {
          id: string;
          order_id: string;
          provider: string;
          provider_ref: string | null;
          status: Database['public']['Enums']['payment_status'];
          amount_cents: number;
          currency: string;
          raw: Json | null;
          created_at: string;
          settled_at: string | null;
        };
        Insert: never;
        Update: never;
        Relationships: [];
      };
      tickets: {
        Row: {
          id: string;
          code: string;
          event_id: string;
          order_item_id: string;
          zone_id: string;
          seat_id: string | null;
          owner_id: string;
          original_owner_id: string;
          holder_name: string | null;
          holder_dni_hash: string | null;
          holder_dni_last4: string | null;
          status: Database['public']['Enums']['ticket_status'];
          face_value_cents: number;
          resale_count: number;
          qr_available_from: string | null;
          issued_at: string;
          used_at: string | null;
        };
        /** Art. 2.1: solo `confirm_payment` crea tickets. */
        Insert: never;
        Update: never;
        Relationships: [
          {
            foreignKeyName: 'tickets_event_id_fkey';
            columns: ['event_id'];
            isOneToOne: false;
            referencedRelation: 'events';
            referencedColumns: ['id'];
          },
        ];
      };
      ticket_events: {
        Row: {
          id: string;
          ticket_id: string;
          actor_id: string | null;
          action: Database['public']['Enums']['ticket_event_action'];
          meta: Json | null;
          corrects_id: string | null;
          created_at: string;
        };
        Insert: never;
        Update: never;
        Relationships: [];
      };
      /** Un caso de soporte. El contexto lo rellena el servidor (009/AC-03). */
      support_cases: {
        Row: {
          id: string;
          code: string;
          kind: Database['public']['Enums']['support_kind'];
          status: Database['public']['Enums']['support_status'];
          priority: Database['public']['Enums']['support_priority'];
          opened_by: string;
          assigned_to: string | null;
          event_id: string | null;
          order_id: string | null;
          ticket_id: string | null;
          checkin_id: string | null;
          subject: string;
          body: string;
          created_at: string;
          updated_at: string;
          resolved_at: string | null;
        };
        /** Solo por RPC: `open_support_case` y `manage_support_case`. */
        Insert: never;
        Update: never;
        Relationships: [];
      };
      /** Append-only (Art. 8.1). `internal` la protege la RLS, no el front. */
      support_messages: {
        Row: {
          id: string;
          case_id: string;
          author_id: string | null;
          body: string;
          internal: boolean;
          created_at: string;
        };
        Insert: never;
        Update: never;
        Relationships: [];
      };
      /** El staff de puerta: un rol POR EVENTO, no del perfil (006). */
      event_staff: {
        Row: {
          id: string;
          event_id: string;
          profile_id: string;
          gate: string;
          zone_id: string | null;
          revoked_at: string | null;
          revoked_by: string | null;
          created_at: string;
          created_by: string | null;
        };
        Insert: {
          event_id: string;
          profile_id: string;
          gate: string;
          zone_id?: string | null;
        };
        /** Solo se revoca o se corrige la puerta. Mover evento o persona reescribiría la bitácora. */
        Update: {
          revoked_at?: string | null;
          revoked_by?: string | null;
          gate?: string;
          zone_id?: string | null;
        };
        Relationships: [];
      };
      /** Append-only, Art. 8.1. `never` en Insert/Update/Delete no es pereza: es la regla. */
      checkins: {
        Row: {
          id: string;
          event_id: string;
          ticket_id: string | null;
          staff_id: string;
          event_staff_id: string | null;
          gate: string;
          result: Database['public']['Enums']['checkin_result'];
          reason: Database['public']['Enums']['checkin_reason'];
          scanned_code: string | null;
          slot_delta: number | null;
          meta: Json | null;
          created_at: string;
        };
        Insert: never;
        Update: never;
        Relationships: [];
      };
      /**
       * 010. Solicitud y amistad son el mismo hecho en dos momentos, así que
       * comparten tabla. `Insert`/`Update` son `never`: solo escriben las RPC
       * `request_friendship` y `respond_friendship` (0052 revoca los dos).
       * Borrar sí está permitido — dejar de ser amigos borra de verdad.
       */
      friend_edges: {
        Row: {
          id: string;
          requester_id: string;
          addressee_id: string;
          status: Database['public']['Enums']['friend_edge_status'];
          created_at: string;
          responded_at: string | null;
        };
        Insert: never;
        Update: never;
        Relationships: [];
      };
      /**
       * 013. Un LIBRO, no un contador: no existe `profiles.points` que alguien
       * pueda ajustar. Append-only (Art. 8.1) — `never` en las tres escrituras
       * no es pereza, es la regla. Lo escribe el trigger de `checkins`.
       */
      /**
       * 012 · Art. 11. Hasta 4, atado a evento, todo o nada. El grupo NO es un
       * mecanismo de compra: decide quién entra y le pasa la lista a
       * `reserve_order`, que es quien hace el todo-o-nada de verdad.
       */
      purchase_groups: {
        Row: {
          id: string;
          event_id: string;
          creator_id: string;
          status: Database['public']['Enums']['purchase_group_status'];
          order_id: string | null;
          created_at: string;
          locked_at: string | null;
        };
        Insert: never;
        Update: never;
        Relationships: [];
      };
      /**
       * `slot` es el árbitro del «hasta 4»: la RPC lo asigna bajo candado y el
       * índice único tumba al segundo si dos calculan el mismo.
       * `order_item_id` es lo que hace que el ticket nazca con su dueño.
       */
      group_members: {
        Row: {
          group_id: string;
          user_id: string;
          event_id: string;
          slot: number;
          order_item_id: string | null;
          joined_at: string;
        };
        Insert: never;
        Update: never;
        Relationships: [];
      };
      point_ledger: {
        Row: {
          id: string;
          user_id: string;
          kind: Database['public']['Enums']['point_reason'];
          points: number;
          event_id: string | null;
          checkin_id: string | null;
          created_at: string;
        };
        Insert: never;
        Update: never;
        Relationships: [];
      };
      /**
       * 011. La mitad «quiere ir» de la señal. La otra mitad se deduce de
       * `tickets`. Sin `status`: quitar el interés borra la fila, así que no se
       * guarda a qué eventos dijo alguien que no.
       */
      event_interests: {
        Row: {
          user_id: string;
          event_id: string;
          created_at: string;
        };
        Insert: {
          user_id?: string;
          event_id: string;
          created_at?: string;
        };
        Update: never;
        Relationships: [];
      };
      /** 010. Solo su dueño lee sus filas: un bloqueo detectable no protege. */
      blocks: {
        Row: {
          blocker_id: string;
          blocked_id: string;
          created_at: string;
        };
        Insert: {
          blocker_id?: string;
          blocked_id: string;
          created_at?: string;
        };
        Update: never;
        Relationships: [];
      };
    };
    Views: {
      /** Catálogo público. La única vista listable por `anon`. */
      v_event_public: {
        Row: {
          id: string | null;
          slug: string | null;
          title: string | null;
          category: string | null;
          hero_image_url: string | null;
          starts_at: string | null;
          doors_at: string | null;
          timezone: string | null;
          capacity: number | null;
          max_per_user: number | null;
          resale_enabled: boolean | null;
          featured_at: string | null;
          /** Para filtrar con `textSearch`, no para seleccionar. */
          search_text: unknown | null;
          venue_name: string | null;
          venue_city: string | null;
          organizer_name: string | null;
          from_price_cents: number | null;
          currency: string | null;
          sale_open: boolean | null;
          next_phase_starts_at: string | null;
          available_now: number | null;
        };
        Relationships: [];
      };
      /**
       * La wallet. `security_invoker = false` porque hace join con events,
       * zones y venues, que están limitadas al organizador — con invoker salía
       * vacía. El filtro `owner_id = auth.uid()` es la única protección.
       */
      v_my_tickets: {
        Row: {
          id: string | null;
          code: string | null;
          status: Database['public']['Enums']['ticket_status'] | null;
          face_value_cents: number | null;
          resale_count: number | null;
          qr_available_from: string | null;
          issued_at: string | null;
          used_at: string | null;
          holder_name: string | null;
          holder_dni_last4: string | null;
          owner_id: string | null;
          event_id: string | null;
          event_slug: string | null;
          event_title: string | null;
          starts_at: string | null;
          doors_at: string | null;
          timezone: string | null;
          event_status: Database['public']['Enums']['event_status'] | null;
          qr_lead_days: number | null;
          resale_enabled: boolean | null;
          max_resales: number | null;
          venue_name: string | null;
          venue_city: string | null;
          zone_name: string | null;
          zone_kind: Database['public']['Enums']['zone_kind'] | null;
          row_label: string | null;
          seat_number: number | null;
          is_past: boolean | null;
          /** El Art. 2 resuelto en el servidor: available | too_early | disabled | spent. */
          qr_state: string | null;
          disabled_reason: string | null;
        };
        Relationships: [];
      };
      /** Disponibilidad por tier. security_invoker: la RLS se aplica dentro. */
      v_event_availability: {
        Row: {
          tier_id: string | null;
          event_id: string | null;
          zone_id: string | null;
          zone_name: string | null;
          segment_id: string | null;
          segment_label: string | null;
          phase_id: string | null;
          phase_name: string | null;
          phase_active: boolean | null;
          price_cents: number | null;
          currency: string | null;
          stock: number | null;
          reserved: number | null;
          sold: number | null;
          available: number | null;
        };
        Relationships: [];
      };
      /** La cola de casos. `opened_by` NO esta: el organizador no sabe quien abrio (D-06). */
      v_support_queue: {
        Row: {
          id: string | null;
          code: string | null;
          kind: Database['public']['Enums']['support_kind'] | null;
          status: Database['public']['Enums']['support_status'] | null;
          priority: Database['public']['Enums']['support_priority'] | null;
          subject: string | null;
          created_at: string | null;
          updated_at: string | null;
          resolved_at: string | null;
          event_id: string | null;
          ticket_id: string | null;
          order_id: string | null;
          checkin_id: string | null;
          assigned_to: string | null;
          event_title: string | null;
          ticket_code: string | null;
          order_code: string | null;
          /** «yo», el nombre real (solo Admin) o «un asistente». Nunca el id. */
          opened_by_label: string | null;
          messages: number | null;
        };
        Relationships: [];
      };
      /** Ventas del evento, Art. 5. bruto = lo cobrado al fan (008/AC-08). */
      v_event_sales: {
        Row: {
          event_id: string | null;
          capacity: number | null;
          service_charge_bps: number | null;
          service_charge_payer: Database['public']['Enums']['charge_payer'] | null;
          payout_policy: Json | null;
          tickets_sold: number | null;
          gross_cents: number | null;
          feventi_commission_cents: number | null;
          refunds_cents: number | null;
          net_estimated_cents: number | null;
        };
        Relationships: [];
      };
      /** Ventas por fase. `phase_id` nulo = la fila agregada «Otras fases» (008/AC-06). */
      v_event_phase_sales: {
        Row: {
          event_id: string | null;
          phase_id: string | null;
          name: string | null;
          kind: Database['public']['Enums']['phase_kind'] | null;
          starts_at: string | null;
          ends_at: string | null;
          sort_order: number | null;
          tickets: number | null;
          gross_cents: number | null;
        };
        Relationships: [];
      };
      /** Los eventos donde este usuario es staff, con su puerta y su turno ya resuelto (006/AC-06). */
      v_my_gate_events: {
        Row: {
          event_id: string | null;
          title: string | null;
          starts_at: string | null;
          doors_at: string | null;
          timezone: string | null;
          event_status: Database['public']['Enums']['event_status'] | null;
          nomination_mode: Database['public']['Enums']['nomination_mode'] | null;
          venue_name: string | null;
          venue_city: string | null;
          venue_address: string | null;
          assignment_id: string | null;
          gate: string | null;
          zone_id: string | null;
          zone_name: string | null;
          shift_from: string | null;
          shift_to: string | null;
          /** Lo calcula el servidor con la MISMA regla que gate_checkin. */
          shift_active: boolean | null;
        };
        Relationships: [];
      };
      /** El contador del turno, agregando checkins (006/AC-26). Nunca un contador incremental. */
      v_gate_stats: {
        Row: {
          event_id: string | null;
          gate: string | null;
          scans: number | null;
          allowed: number | null;
          manual_review: number | null;
          already_used: number | null;
          denied: number | null;
          screenshots: number | null;
          tickets_total: number | null;
          tickets_used: number | null;
        };
        Relationships: [];
      };
      /**
       * 010. Definer (0054), como `v_my_tickets`: `profiles` solo lo lee su
       * dueño. Emite `full_name` y `avatar_url` de un amigo aceptado, y nada
       * más — nunca `ninja_mode`, que si llegara al front rompería la función.
       */
      v_my_friends: {
        Row: {
          edge_id: string | null;
          friend_id: string | null;
          full_name: string | null;
          avatar_url: string | null;
          since: string | null;
        };
        Relationships: [];
      };
      /** 013. Una fila, una columna: el saldo. `coalesce` a 0, nunca null. */
      v_my_points: {
        Row: {
          total: number | null;
        };
        Relationships: [];
      };
      /**
       * 011. Definer, y por eso el `where` de la vista es la única frontera.
       * Emite **solo conteos** (D-40): nunca zona, precio, cantidad, id de
       * orden ni quién. Un evento sin ningún amigo no sale — cero no es un
       * valor que enseñar.
       */
      v_my_event_signals: {
        Row: {
          event_id: string | null;
          friends_going: number | null;
          friends_interested: number | null;
          /** Hasta dos nombres de PILA. El resto lo cuenta el número (D-46). */
          going_names: string[] | null;
          interested_names: string[] | null;
        };
        Relationships: [];
      };
      v_my_friend_requests: {
        Row: {
          edge_id: string | null;
          requester_id: string | null;
          full_name: string | null;
          avatar_url: string | null;
          created_at: string | null;
        };
        Relationships: [];
      };
    };
    Functions: {
      /**
       * Modo DNI del validador (D-03). Devuelve nombre y últimos 4, nunca el hash.
       *
       * `gate_checkin` NO está aquí a propósito: es solo de `service_role`, y se
       * llama desde la Edge Function `qr-validate`. Si apareciera en estos tipos,
       * alguien la llamaría desde el front y se encontraría un 403 en la puerta.
       */
      gate_find_by_dni: { Args: { p_event_id: string; p_dni: string }; Returns: Json };
      /**
       * Abre un caso. El cliente manda el OBJETO; el evento y la orden los
       * rellena el servidor desde el ticket (009/AC-03).
       */
      open_support_case: {
        Args: {
          p_kind: Database['public']['Enums']['support_kind'];
          p_subject: string;
          p_body: string;
          p_ticket_id?: string | null;
          p_order_id?: string | null;
          p_event_id?: string | null;
          p_checkin_id?: string | null;
        };
        Returns: string;
      };
      post_support_message: {
        Args: { p_case_id: string; p_body: string; p_internal?: boolean };
        Returns: string;
      };
      /** Solo Admin. Estado, prioridad, asignación y nota interna, en un sitio. */
      manage_support_case: {
        Args: {
          p_case_id: string;
          p_status?: Database['public']['Enums']['support_status'] | null;
          p_priority?: Database['public']['Enums']['support_priority'] | null;
          p_assign?: string | null;
          p_note?: string | null;
        };
        Returns: undefined;
      };
      /** Solo Admin. Deja asiento en ticket_events con el caso en meta (Art. 8.3). */
      admin_ticket_action: {
        Args: {
          p_case_id: string;
          p_ticket_id: string;
          p_action: Database['public']['Enums']['ticket_event_action'];
          p_note?: string | null;
          p_corrects?: string | null;
        };
        Returns: string;
      };
      /** Detalle público por slug: acepta `unlisted`, y por eso no es una vista. */
      get_public_event: { Args: { p_slug: string }; Returns: Json };
      /** Devuelve el id de la orden. Ver specs/004-checkout-emision/plan.md. */
      reserve_order: { Args: { p_event_id: string; p_items: Json }; Returns: string };
      set_item_attendee: {
        Args: { p_item_id: string; p_name: string; p_dni: string };
        Returns: undefined;
      };
      start_payment: { Args: { p_order_id: string }; Returns: undefined };
      fail_payment: { Args: { p_order_id: string; p_reason?: string }; Returns: undefined };
      /** La consulta usa la misma configuración que el índice, o unaccent no aplica. */
      search_events_tsquery: { Args: { p_query: string }; Returns: unknown };
      active_phase_id: { Args: { p_event_id: string }; Returns: string | null };
      generate_seats: {
        Args: { p_zone_id: string; p_rows: string[]; p_per_row: number; p_segment_id?: string };
        Returns: number;
      };
      create_event: { Args: { p_organizer_id: string; p_title?: string }; Returns: string };
      submit_event: { Args: { p_event_id: string }; Returns: undefined };
      approve_event: { Args: { p_event_id: string; p_note?: string }; Returns: undefined };
      reject_event: { Args: { p_event_id: string; p_note: string }; Returns: undefined };
      request_event_info: {
        Args: { p_event_id: string; p_note: string; p_checklist?: Json };
        Returns: undefined;
      };
      set_event_checklist: {
        Args: { p_event_id: string; p_checklist: Json };
        Returns: undefined;
      };
      publish_event: { Args: { p_event_id: string }; Returns: undefined };
      pause_event: { Args: { p_event_id: string; p_note?: string }; Returns: undefined };
      resume_event: { Args: { p_event_id: string; p_note?: string }; Returns: undefined };
      cancel_event: { Args: { p_event_id: string; p_note: string }; Returns: undefined };
      /**
       * 010. Los CUATRO casos de fallo devuelven el mismo error, y el front
       * enseña ese mismo texto también en el éxito: distinguirlos convertiría
       * el formulario en un oráculo de «¿está esta persona registrada?».
       */
      /** 012 · Art. 11. Devuelve el id del grupo; el creador entra como slot 1. */
      create_purchase_group: { Args: { p_event_id: string }; Returns: string };
      /** Solo el creador, y solo a un amigo: `private.are_friends` lo comprueba. */
      add_group_member: { Args: { p_group_id: string; p_user_id: string }; Returns: undefined };
      leave_purchase_group: { Args: { p_group_id: string }; Returns: undefined };
      /** Exige tantos ítems como miembros: el todo-o-nada, en una comparación. */
      lock_purchase_group: { Args: { p_group_id: string; p_order_id: string }; Returns: undefined };
      request_friendship: { Args: { target_email: string }; Returns: undefined };
      respond_friendship: { Args: { edge_id: string; accept: boolean }; Returns: undefined };
      block_user: { Args: { target_id: string }; Returns: undefined };
      set_event_featured: {
        Args: { p_event_id: string; p_featured: boolean };
        Returns: undefined;
      };
      create_organizer: {
        Args: {
          p_legal_name: string;
          p_trade_name?: string;
          p_ruc?: string;
          p_contact_email?: string;
          p_contact_phone?: string;
        };
        Returns: string;
      };
      add_organizer_member: {
        Args: {
          p_organizer_id: string;
          p_user_id: string;
          p_role?: Database['public']['Enums']['organizer_role'];
        };
        Returns: undefined;
      };
      revoke_organizer_member: {
        Args: { p_organizer_id: string; p_user_id: string };
        Returns: undefined;
      };
      approve_organizer: { Args: { p_organizer_id: string }; Returns: undefined };
      set_organizer_status: {
        Args: {
          p_organizer_id: string;
          p_status: Database['public']['Enums']['organizer_status'];
        };
        Returns: undefined;
      };
      set_own_dni: { Args: { p_dni: string }; Returns: undefined };
      verify_dni: { Args: { p_user_id: string }; Returns: undefined };
    };
    Enums: {
      app_role: 'fan' | 'organizer' | 'staff' | 'admin';
      organizer_role: 'owner' | 'admin' | 'viewer';
      organizer_status: 'draft' | 'pending' | 'approved' | 'rejected' | 'suspended';
      charge_payer: 'fan' | 'organizer';
      nomination_mode: 'strict' | 'flexible';
      event_visibility: 'public' | 'unlisted' | 'private';
      zone_kind: 'standing' | 'seated';
      phase_kind: 'presale' | 'regular' | 'fanpass_presale';
      order_status:
        | 'draft'
        | 'reserved'
        | 'awaiting_payment'
        | 'paid'
        | 'failed'
        | 'expired'
        | 'refunded'
        | 'cancelled';
      payment_status: 'pending' | 'succeeded' | 'failed' | 'refunded' | 'disputed';
      ticket_status: 'active' | 'listed' | 'transferred' | 'used' | 'void' | 'refunded';
      /** D-12: refund, cancellation y disputa son tres procesos distintos. */
      support_kind:
        | 'payment' | 'ticket' | 'qr' | 'resale' | 'courtesy'
        | 'group' | 'refund' | 'cancellation' | 'ownership' | 'other';
      support_status:
        | 'open' | 'waiting_user' | 'in_progress' | 'escalated' | 'resolved' | 'closed';
      support_priority: 'low' | 'normal' | 'high' | 'urgent';
      /** 013. Solo `checkin` por ahora. D-45: por asistir, no por comprar. */
      point_reason: 'checkin';
      /**
       * 010. Dos valores, no tres. «Rechazada» NO es un estado: es la ausencia
       * de la fila. Guardar rechazos deja a quien pide saber que lo rechazaron.
       */
      /** 012. `cancelled` es un estado, no un borrado: el grupo deja rastro. */
      purchase_group_status: 'open' | 'locked' | 'completed' | 'cancelled';
      friend_edge_status: 'pending' | 'accepted';
      /** Los cuatro del mockup. No hay un quinto, y el enum lo garantiza. */
      checkin_result: 'allowed' | 'manual_review' | 'already_used' | 'denied';
      checkin_reason:
        | 'ok'
        | 'not_nominated'
        | 'wrong_zone'
        | 'dni_mode'
        | 'already_used'
        | 'qr_unreadable'
        | 'screenshot_suspected'
        | 'wrong_event'
        | 'event_cancelled'
        | 'ticket_listed'
        | 'ticket_transferred'
        | 'ticket_void'
        | 'ticket_refunded';
      ticket_event_action:
        | 'issued'
        | 'nominated'
        | 'listed'
        | 'unlisted'
        | 'transferred'
        | 'used'
        | 'voided'
        | 'refunded'
        | 'corrected';
      event_status:
        | 'draft'
        | 'pending_review'
        | 'changes_requested'
        | 'rejected'
        | 'approved'
        | 'setup'
        | 'published'
        | 'paused'
        | 'cancelled'
        | 'finished';
      review_action:
        | 'submitted'
        | 'info_requested'
        | 'approved'
        | 'rejected'
        | 'published'
        | 'paused'
        | 'cancelled'
        | 'note';
    };
    CompositeTypes: { [_ in never]: never };
  };
};

export const Constants = {
  public: {
    Enums: {
      app_role: ['fan', 'organizer', 'staff', 'admin'],
      organizer_role: ['owner', 'admin', 'viewer'],
      organizer_status: ['draft', 'pending', 'approved', 'rejected', 'suspended'],
      charge_payer: ['fan', 'organizer'],
      nomination_mode: ['strict', 'flexible'],
      event_visibility: ['public', 'unlisted', 'private'],
      zone_kind: ['standing', 'seated'],
      phase_kind: ['presale', 'regular', 'fanpass_presale'],
      order_status: [
        'draft','reserved','awaiting_payment','paid','failed','expired','refunded','cancelled',
      ],
      payment_status: ['pending', 'succeeded', 'failed', 'refunded', 'disputed'],
      ticket_status: ['active', 'listed', 'transferred', 'used', 'void', 'refunded'],
      ticket_event_action: [
        'issued','nominated','listed','unlisted','transferred','used','voided','refunded','corrected',
      ],
      event_status: [
        'draft',
        'pending_review',
        'changes_requested',
        'rejected',
        'approved',
        'setup',
        'published',
        'paused',
        'cancelled',
        'finished',
      ],
      review_action: [
        'submitted',
        'info_requested',
        'approved',
        'rejected',
        'published',
        'paused',
        'cancelled',
        'note',
      ],
    },
  },
} as const;

type PublicSchema = Database['public'];

export type Tables<T extends keyof (PublicSchema['Tables'] & PublicSchema['Views'])> =
  (PublicSchema['Tables'] & PublicSchema['Views'])[T]['Row'];
export type TablesInsert<T extends keyof PublicSchema['Tables']> =
  PublicSchema['Tables'][T]['Insert'];
export type TablesUpdate<T extends keyof PublicSchema['Tables']> =
  PublicSchema['Tables'][T]['Update'];
export type Enums<T extends keyof PublicSchema['Enums']> = PublicSchema['Enums'][T];
