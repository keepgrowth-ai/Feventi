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
    };
    Views: { [_ in never]: never };
    Functions: {
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

export type Tables<T extends keyof PublicSchema['Tables']> = PublicSchema['Tables'][T]['Row'];
export type TablesInsert<T extends keyof PublicSchema['Tables']> =
  PublicSchema['Tables'][T]['Insert'];
export type TablesUpdate<T extends keyof PublicSchema['Tables']> =
  PublicSchema['Tables'][T]['Update'];
export type Enums<T extends keyof PublicSchema['Enums']> = PublicSchema['Enums'][T];
