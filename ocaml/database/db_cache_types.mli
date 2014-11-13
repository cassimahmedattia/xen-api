(*
 * Copyright (C) 2006-2014 Citrix Systems Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published
 * by the Free Software Foundation; version 2.1 only. with the special
 * exception on linking described in file LICENSE.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *)

module Value : sig
        type t = string
        (** A value stored in the database *)

end

module Time : sig
        type t = Generation.t
        (** A monotonically increasing counter associated with this database *)
end

module Stat : sig
        type t = {
                created: Time.t;  (** Time this value was created *)
                modified: Time.t; (** Time this value was last modified *)
                deleted: Time.t;  (** Time this value was deleted (or 0L meaning it is still alive) *)
        }
        (** Metadata associated with a database value *)
end

module type MAP = sig
        type t
        (** A map from string to some value *)

        type value
        (** The type of the values in the map *)

        val empty : t
        (** The empty map *)

        val add: Time.t -> string -> value -> t -> t
        (** [add now key value map] returns a new map with [key] associated with [value],
            with creation time [now] *)

        val fold : (string -> Stat.t -> value -> 'b -> 'b) -> t -> 'b -> 'b
        (** [fold f t initial] folds [f key stats value acc] over the items in [t] *)

        val fold_over_recent : Time.t -> (string -> Stat.t -> value -> 'b -> 'b) -> t -> 'b -> 'b
        (** [fold_over_recent since f t initial] folds [f key stats value acc] over all the
            items with a modified time larger than [since] *)

        val find : string -> t -> value
        (** [find key t] returns the value associated with [key] in [t] or raises
            [DBCache_NotFound] *)

        val mem : string -> t -> bool
        (** [mem key t] returns true if [value] is associated with [key] in [t] or false
            otherwise *)

        val iter : (string -> value -> unit) -> t -> unit
        (** [iter f t] applies [f key value] to each binding in [t] *)

        val update : Time.t -> string -> value -> (value -> value) -> t -> t
        (** [update now key default f t] returns a new map which is the same as [t] except:
            if there is a value associated with [key] it is replaced with [f key[
            or if there is no value associated with [key] then [default] is associated with [key]
          *)
end

module Row : sig
        include MAP
          with type value = Value.t

        val add_defaults: Time.t -> Schema.Table.t -> t -> t
        (** [add_defaults now schema t]: returns a row which is [t] extended to contain
            all the columns specified in the schema, with default values set if not already
            in [t]. If the schema is missing a default value then raises [DBCache_NotFound]:
            this would happen if a client failed to provide a necessary field. *)

        val remove : string -> t -> t
        (** [remove key t] removes the binding of [key] from [t]. *)
end

module Table : sig
        include MAP
          with type value = Row.t

        val update_generation : Time.t -> string -> value -> (value -> value) -> t -> t
        val rows : t -> value list
        val remove : Time.t -> string -> t -> t
        val fold_over_deleted : Time.t -> (string -> Stat.t -> 'b -> 'b) -> t -> 'b -> 'b
end

module TableSet : sig
        include MAP
          with type value = Table.t
        val remove : string -> t -> t
end

module Manifest :
  sig
    type t
    val empty : t
    val make : int -> int -> Generation.t -> t
    val generation : t -> Generation.t
    val update_generation : (Generation.t -> Generation.t) -> t -> t
    val next : t -> t
	val schema : t -> int * int
	val update_schema : ((int * int) option -> (int * int) option) -> t -> t
  end

(** The core database updates (RefreshRow and PreDelete is more of an 'event') *)
type update = 
	| RefreshRow of string (* tblname *) * string (* objref *)
	| WriteField of string (* tblname *) * string (* objref *) * string (* fldname *) * string  (* oldval *) * string (* newval *)
	| PreDelete of string (* tblname *) * string (* objref *)
	| Delete of string (* tblname *) * string (* objref *) * (string * string) list (* values *)
	| Create of string (* tblname *) * string (* objref *) * (string * string) list (* values *)

module Database :
  sig
    type t
    val update_manifest : (Manifest.t -> Manifest.t) -> t -> t
    val update_tableset : (TableSet.t -> TableSet.t) -> t -> t
    val manifest : t -> Manifest.t
	val tableset : t -> TableSet.t
	val schema : t -> Schema.t
    val increment : t -> t
    val update : (TableSet.t -> TableSet.t) -> t -> t
    val set_generation : Generation.t -> t -> t
    val make : Schema.t -> t

	val table_of_ref : string -> t -> string
	val lookup_key : string -> t -> (string * string) option
	val reindex : t -> t

	val register_callback : string -> (update -> t -> unit) -> t -> t
	val unregister_callback : string -> t -> t
	val notify : update -> t -> unit
  end

exception Duplicate
val add_to_set : string -> string -> string
val remove_from_set : string -> string -> string
val add_to_map : string -> string -> string -> string
val remove_from_map : string -> string -> string

val set_field : string -> string -> string -> string -> Database.t -> Database.t
val get_field : string -> string -> string -> Database.t -> string
val remove_row : string -> string -> Database.t -> Database.t
val add_row : string -> string -> Row.t -> Database.t -> Database.t

val update_generation : string -> string -> Database.t -> Database.t

type where_record = {
	table: string;       (** table from which ... *)
	return: string;      (** we'd like to return this field... *)
	where_field: string; (** where this other field... *)
	where_value: string; (** contains this value *)
}
val where_record_of_rpc: Rpc.t -> where_record
val rpc_of_where_record: where_record -> Rpc.t

type structured_op_t = 
	| AddSet
	| RemoveSet
	| AddMap
	| RemoveMap
val structured_op_t_of_rpc: Rpc.t -> structured_op_t
val rpc_of_structured_op_t: structured_op_t -> Rpc.t
