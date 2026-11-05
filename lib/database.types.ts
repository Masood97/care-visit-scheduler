
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {
  
  "public": {
          Tables: {
            "audit_log": {
                  Row: {
                    "action": Database["public"]['Enums']["audit_action"],"changed_at": string,"changed_by": string | null,"id": number,"new_data": Json | null,"old_data": Json | null,"organization_id": string,"row_id": string,"table_name": string
                  }
                  ComputedFields: never
                  Insert: {
                    "action": Database["public"]['Enums']["audit_action"],"changed_at"?: string,"changed_by"?: string | null,"id"?: never,"new_data"?: Json | null,"old_data"?: Json | null,"organization_id": string,"row_id": string,"table_name": string
                  }
                  Update: {
                    "action"?: Database["public"]['Enums']["audit_action"],"changed_at"?: string,"changed_by"?: string | null,"id"?: never,"new_data"?: Json | null,"old_data"?: Json | null,"organization_id"?: string,"row_id"?: string,"table_name"?: string
                  }
                  Relationships: [
                    
                  ]
                },"clients": {
                  Row: {
                    "address": string,"created_at": string,"full_name": string,"id": string,"latitude": number,"longitude": number,"organization_id": string,"status": Database["public"]['Enums']["client_status"],"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "address": string,"created_at"?: string,"full_name": string,"id"?: string,"latitude": number,"longitude": number,"organization_id": string,"status"?: Database["public"]['Enums']["client_status"],"updated_at"?: string
                  }
                  Update: {
                    "address"?: string,"created_at"?: string,"full_name"?: string,"id"?: string,"latitude"?: number,"longitude"?: number,"organization_id"?: string,"status"?: Database["public"]['Enums']["client_status"],"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "clients_organization_id_fkey"
      columns: ["organization_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    }
                  ]
                },"organization_members": {
                  Row: {
                    "created_at": string,"full_name": string,"organization_id": string,"role": Database["public"]['Enums']["member_role"],"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"full_name": string,"organization_id": string,"role": Database["public"]['Enums']["member_role"],"user_id": string
                  }
                  Update: {
                    "created_at"?: string,"full_name"?: string,"organization_id"?: string,"role"?: Database["public"]['Enums']["member_role"],"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "organization_members_organization_id_fkey"
      columns: ["organization_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    }
                  ]
                },"organizations": {
                  Row: {
                    "created_at": string,"id": string,"name": string,"time_zone": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"id"?: string,"name": string,"time_zone": string,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"id"?: string,"name"?: string,"time_zone"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"visit_events": {
                  Row: {
                    "distance_m": number,"event_type": Database["public"]['Enums']["visit_event_type"],"id": string,"latitude": number,"longitude": number,"occurred_at": string,"organization_id": string,"visit_id": string,"worker_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "distance_m": number,"event_type": Database["public"]['Enums']["visit_event_type"],"id"?: string,"latitude": number,"longitude": number,"occurred_at"?: string,"organization_id": string,"visit_id": string,"worker_id": string
                  }
                  Update: {
                    "distance_m"?: number,"event_type"?: Database["public"]['Enums']["visit_event_type"],"id"?: string,"latitude"?: number,"longitude"?: number,"occurred_at"?: string,"organization_id"?: string,"visit_id"?: string,"worker_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "visit_events_visit_fk"
      columns: ["organization_id","visit_id"]
isOneToOne: false
      referencedRelation: "visits"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "visit_events_worker_fk"
      columns: ["organization_id","worker_id"]
isOneToOne: false
      referencedRelation: "organization_members"
      referencedColumns: ["organization_id","user_id"]
    }
                  ]
                },"visits": {
                  Row: {
                    "client_id": string,"created_at": string,"ends_at": string,"id": string,"notes": string | null,"organization_id": string,"starts_at": string,"status": Database["public"]['Enums']["visit_status"],"updated_at": string,"worker_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "client_id": string,"created_at"?: string,"ends_at": string,"id"?: string,"notes"?: string | null,"organization_id": string,"starts_at": string,"status"?: Database["public"]['Enums']["visit_status"],"updated_at"?: string,"worker_id": string
                  }
                  Update: {
                    "client_id"?: string,"created_at"?: string,"ends_at"?: string,"id"?: string,"notes"?: string | null,"organization_id"?: string,"starts_at"?: string,"status"?: Database["public"]['Enums']["visit_status"],"updated_at"?: string,"worker_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "visits_client_fk"
      columns: ["organization_id","client_id"]
isOneToOne: false
      referencedRelation: "clients"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "visits_organization_id_fkey"
      columns: ["organization_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "visits_worker_fk"
      columns: ["organization_id","worker_id"]
isOneToOne: false
      referencedRelation: "organization_members"
      referencedColumns: ["organization_id","user_id"]
    }
                  ]
                }
          }
          Views: {
            "worker_weekly_hours": {
                  Row: {
                    "hours": number | null,"organization_id": string,"visits_completed": number | null,"week_start": string | null,"worker_id": string,"worker_name": string
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "visit_events_worker_fk"
      columns: ["organization_id","worker_id"]
isOneToOne: false
      referencedRelation: "organization_members"
      referencedColumns: ["organization_id","user_id"]
    }
                  ]
                }
          }
          Functions: {
            "check_in":
{ Args: { "p_lat": number,"p_lng": number,"p_visit_id": string }; Returns: {
              "distance_m": number,
"event_type": Database["public"]['Enums']["visit_event_type"],
"id": string,
"latitude": number,
"longitude": number,
"occurred_at": string,
"organization_id": string,
"visit_id": string,
"worker_id": string
            }
                          SetofOptions: {
        from: "*"
        to: "visit_events"
        isOneToOne: true
        isSetofReturn: false
      } },
"check_out":
{ Args: { "p_lat": number,"p_lng": number,"p_visit_id": string }; Returns: {
              "distance_m": number,
"event_type": Database["public"]['Enums']["visit_event_type"],
"id": string,
"latitude": number,
"longitude": number,
"occurred_at": string,
"organization_id": string,
"visit_id": string,
"worker_id": string
            }
                          SetofOptions: {
        from: "*"
        to: "visit_events"
        isOneToOne: true
        isSetofReturn: false
      } }
          }
          Enums: {
            "audit_action": "insert"|"update"|"delete","client_status": "active"|"archived","member_role": "owner"|"coordinator"|"worker","visit_event_type": "check_in"|"check_out","visit_status": "scheduled"|"in_progress"|"completed"|"cancelled"
          }
          CompositeTypes: {
            [_ in never]: never
          }
        }
}

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
  ? (DefaultSchema["Tables"] & DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
      Row: infer R
    }
    ? R
    : never
  : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Insert: infer I
    }
    ? I
    : never
  : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Update: infer U
    }
    ? U
    : never
  : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
  ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
  : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never
> = PublicCompositeTypeNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
  ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
  : never

export const Constants = {
  "public": {
          Enums: {
            "audit_action": ["insert", "update", "delete"],"client_status": ["active", "archived"],"member_role": ["owner", "coordinator", "worker"],"visit_event_type": ["check_in", "check_out"],"visit_status": ["scheduled", "in_progress", "completed", "cancelled"]
          }
        }
} as const
