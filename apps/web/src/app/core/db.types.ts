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
    };
    Functions: {
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
