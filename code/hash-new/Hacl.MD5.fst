module Hacl.MD5

include Hacl.Hash.Common
open Spec.Hash.Helpers

module B = LowStar.Buffer
module HS = FStar.HyperStack
module HST = FStar.HyperStack.ST
module Spec = Spec.MD5
module U8 = FStar.UInt8
module U32 = FStar.UInt32
module E = FStar.Kremlin.Endianness
module CE = C.Endianness

friend Spec.MD5

(** Top-level constant arrays for the MD5 algorithm. *)
let h0 = B.gcmalloc_of_list HS.root Spec.init_as_list
let t = B.gcmalloc_of_list HS.root Spec.t_as_list

(* We believe it'll be hard to get, "for free", within this module:
     readonly h224 /\ writable client_state ==> disjoint h224 client_state
   so, instead, we require the client to do a little bit of reasoning to show
   that their buffers are disjoint from our top-level readonly state. *)

let alloca () =
  B.alloca_of_list Spec.init_as_list

(* The total footprint of our morally readonly data. *)
let static_fp () =
  B.loc_union (B.loc_addr_of_buffer h0) (B.loc_addr_of_buffer t)
  
let recall_static_fp () =
  B.recall h0;
  B.recall t

let init s =
  B.recall h0;
  // waiting for monotonicity
  let h = HST.get () in
  assume (B.as_seq h h0 == Seq.seq_of_list Spec.init_as_list);
  B.blit h0 0ul s 0ul 4ul

inline_for_extraction
let abcd_t = (b: B.buffer U32.t { B.length b == 4 } )

inline_for_extraction
let abcd_idx = (n: U32.t { U32.v n < 4 } )

inline_for_extraction
let x_idx = (n: U32.t { U32.v n < 16 } )

inline_for_extraction
let x_t = (b: B.buffer U8.t { B.length b == 64 } )

inline_for_extraction
let t_idx = (n: U32.t { 1 <= U32.v n /\ U32.v n <= 64 } )

inline_for_extraction
let (<<<) = Spec.rotl

inline_for_extraction
val round_op_gen
  (f: (U32.t -> U32.t -> U32.t -> Tot U32.t))
  (abcd: abcd_t)
  (x: x_t)
  (a b c d: abcd_idx)
  (k: x_idx)
  (s: Spec.rotate_idx)
  (i: t_idx)
: HST.Stack unit
  (requires (fun h ->
    B.live h abcd /\
    B.live h x /\
    B.loc_disjoint (B.loc_union (B.loc_buffer x) (B.loc_buffer abcd)) (static_fp ()) /\
    B.disjoint abcd x
  ))
  (ensures (fun h _ h' ->
    B.modifies (B.loc_buffer abcd) h h' /\
    B.live h' abcd /\
    B.live h' x /\ // better to add this here also to ease chaining
    B.as_seq h' abcd == Spec.round_op_gen f (B.as_seq h abcd) (E.seq_uint32_of_be 16 (B.as_seq h x)) (U32.v a) (U32.v b) (U32.v c) (U32.v d) (U32.v k) s (U32.v i)
  ))

#reset-options "--z3rlimit 16" // --using_facts_from '* -FStar.Int8 -FStar.Int16 -FStar.Int32 -FStar.Int64 -FStar.Int128 -FStar.UInt16 -FStar.UInt64 -FStar.UInt128'"

let round_op_gen f abcd x a b c d k s i =
  let h = HST.get () in
  B.recall t;
  // waiting for monotonicity
  let h_ = HST.get () in
  assume (B.as_seq h_ t == Spec.t);
  assert_norm (64 / 4 == 16);
  assert_norm (64 % 4 == 0);
  let sx = Ghost.hide (E.seq_uint32_of_be 16 (B.as_seq h x)) in
  let va = B.index abcd a in
  let vb = B.index abcd b in
  let vc = B.index abcd c in
  let vd = B.index abcd d in
  let xk = CE.index_32_be x k in
  assert (xk == Seq.index (Ghost.reveal sx) (U32.v k));
  let ti = B.index t (i `U32.sub` 1ul) in
  assert (ti == Seq.index Spec.t (U32.v i - 1));
  let v = (vb `U32.add_mod` ((va `U32.add_mod` f vb vc vd `U32.add_mod` xk `U32.add_mod` ti) <<< s)) in
  B.upd abcd a v;
  let h' = HST.get () in
  ()

#reset-options

inline_for_extraction let ia : abcd_idx = 0ul
inline_for_extraction let ib : abcd_idx = 1ul
inline_for_extraction let ic : abcd_idx = 2ul
inline_for_extraction let id : abcd_idx = 3ul

inline_for_extraction
let round1_op = round_op_gen Spec.f

inline_for_extraction
let round1
  (abcd: abcd_t)
  (x: x_t)
: HST.Stack unit
  (requires (fun h ->
    B.live h abcd /\
    B.live h x /\
    B.loc_disjoint (B.loc_union (B.loc_buffer x) (B.loc_buffer abcd)) (static_fp ()) /\
    B.disjoint abcd x
  ))
  (ensures (fun h _ h' ->
    B.modifies (B.loc_buffer abcd) h h' /\
    B.live h' abcd /\
    B.live h' x /\
    B.as_seq h' abcd == Spec.round1 (B.as_seq h abcd) (E.seq_uint32_of_be 16 (B.as_seq h x))
  ))
=
  let _ = round1_op abcd x ia ib ic id  0ul  7ul  1ul in
  let _ = round1_op abcd x id ia ib ic  1ul 12ul  2ul in
  let _ = round1_op abcd x ic id ia ib  2ul 17ul  3ul in
  let _ = round1_op abcd x ib ic id ia  3ul 22ul  4ul in

  let _ = round1_op abcd x ia ib ic id 4ul 7ul 5ul in
  let _ = round1_op abcd x id ia ib ic 5ul 12ul 6ul in
  let _ = round1_op abcd x ic id ia ib 6ul 17ul 7ul in
  let _ = round1_op abcd x ib ic id ia 7ul 22ul 8ul in

  let _ = round1_op abcd x ia ib ic id 8ul 7ul 9ul in
  let _ = round1_op abcd x id ia ib ic 9ul 12ul 10ul in
  let _ = round1_op abcd x ic id ia ib 10ul 17ul 11ul in
  let _ = round1_op abcd x ib ic id ia 11ul 22ul 12ul in

  let _ = round1_op abcd x ia ib ic id 12ul 7ul 13ul in
  let _ = round1_op abcd x id ia ib ic 13ul 12ul 14ul in
  let _ = round1_op abcd x ic id ia ib 14ul 17ul 15ul in
  let _ = round1_op abcd x ib ic id ia 15ul 22ul 16ul in

  ()

inline_for_extraction
let round2_op = round_op_gen Spec.g

inline_for_extraction
let round2
  (abcd: abcd_t)
  (x: x_t)
: HST.Stack unit
  (requires (fun h ->
    B.live h abcd /\
    B.live h x /\
    B.loc_disjoint (B.loc_union (B.loc_buffer x) (B.loc_buffer abcd)) (static_fp ()) /\
    B.disjoint abcd x
  ))
  (ensures (fun h _ h' ->
    B.modifies (B.loc_buffer abcd) h h' /\
    B.live h' abcd /\
    B.live h' x /\
    B.as_seq h' abcd == Spec.round2 (B.as_seq h abcd) (E.seq_uint32_of_be 16 (B.as_seq h x))
  ))
=
  let _ = round2_op abcd x ia ib ic id 1ul 5ul 17ul in
  let _ = round2_op abcd x id ia ib ic 6ul 9ul 18ul in
  let _ = round2_op abcd x ic id ia ib 11ul 14ul 19ul in
  let _ = round2_op abcd x ib ic id ia 0ul 20ul 20ul in

  let _ = round2_op abcd x ia ib ic id 5ul 5ul 21ul in
  let _ = round2_op abcd x id ia ib ic 10ul 9ul 22ul in
  let _ = round2_op abcd x ic id ia ib 15ul 14ul 23ul in
  let _ = round2_op abcd x ib ic id ia 4ul 20ul 24ul in

  let _ = round2_op abcd x ia ib ic id 9ul 5ul 25ul in
  let _ = round2_op abcd x id ia ib ic 14ul 9ul 26ul in
  let _ = round2_op abcd x ic id ia ib 3ul 14ul 27ul in
  let _ = round2_op abcd x ib ic id ia 8ul 20ul 28ul in

  let _ = round2_op abcd x ia ib ic id 13ul 5ul 29ul in
  let _ = round2_op abcd x id ia ib ic 2ul 9ul 30ul in
  let _ = round2_op abcd x ic id ia ib 7ul 14ul 31ul in
  let _ = round2_op abcd x ib ic id ia 12ul 20ul 32ul in

  ()

inline_for_extraction
let round3_op = round_op_gen Spec.h

inline_for_extraction
let round3
  (abcd: abcd_t)
  (x: x_t)
: HST.Stack unit
  (requires (fun h ->
    B.live h abcd /\
    B.live h x /\
    B.loc_disjoint (B.loc_union (B.loc_buffer x) (B.loc_buffer abcd)) (static_fp ()) /\
    B.disjoint abcd x
  ))
  (ensures (fun h _ h' ->
    B.modifies (B.loc_buffer abcd) h h' /\
    B.live h' abcd /\
    B.live h' x /\
    B.as_seq h' abcd == Spec.round3 (B.as_seq h abcd) (E.seq_uint32_of_be 16 (B.as_seq h x))
  ))
=
  let _ = round3_op abcd x ia ib ic id 5ul 4ul 33ul in
  let _ = round3_op abcd x id ia ib ic 8ul 11ul 34ul in
  let _ = round3_op abcd x ic id ia ib 11ul 16ul 35ul in
  let _ = round3_op abcd x ib ic id ia 14ul 23ul 36ul in

  let _ = round3_op abcd x ia ib ic id 1ul 4ul 37ul in
  let _ = round3_op abcd x id ia ib ic 4ul 11ul 38ul in
  let _ = round3_op abcd x ic id ia ib 7ul 16ul 39ul in
  let _ = round3_op abcd x ib ic id ia 10ul 23ul 40ul in

  let _ = round3_op abcd x ia ib ic id 13ul 4ul 41ul in
  let _ = round3_op abcd x id ia ib ic 0ul 11ul 42ul in
  let _ = round3_op abcd x ic id ia ib 3ul 16ul 43ul in
  let _ = round3_op abcd x ib ic id ia 6ul 23ul 44ul in

  let _ = round3_op abcd x ia ib ic id 9ul 4ul 45ul in
  let _ = round3_op abcd x id ia ib ic 12ul 11ul 46ul in
  let _ = round3_op abcd x ic id ia ib 15ul 16ul 47ul in
  let _ = round3_op abcd x ib ic id ia 2ul 23ul 48ul in

  ()

inline_for_extraction
let round4_op = round_op_gen Spec.i

inline_for_extraction
let round4
  (abcd: abcd_t)
  (x: x_t)
: HST.Stack unit
  (requires (fun h ->
    B.live h abcd /\
    B.live h x /\
    B.loc_disjoint (B.loc_union (B.loc_buffer x) (B.loc_buffer abcd)) (static_fp ()) /\
    B.disjoint abcd x
  ))
  (ensures (fun h _ h' ->
    B.modifies (B.loc_buffer abcd) h h' /\
    B.live h' abcd /\
    B.live h' x /\
    B.as_seq h' abcd == Spec.round4 (B.as_seq h abcd) (E.seq_uint32_of_be 16 (B.as_seq h x))
  ))
=
  let _ = round4_op abcd x ia ib ic id 0ul 6ul 49ul in
  let _ = round4_op abcd x id ia ib ic 7ul 10ul 50ul in
  let _ = round4_op abcd x ic id ia ib 14ul 15ul 51ul in
  let _ = round4_op abcd x ib ic id ia 5ul 21ul 52ul in

  let _ = round4_op abcd x ia ib ic id 12ul 6ul 53ul in
  let _ = round4_op abcd x id ia ib ic 3ul 10ul 54ul in
  let _ = round4_op abcd x ic id ia ib 10ul 15ul 55ul in
  let _ = round4_op abcd x ib ic id ia 1ul 21ul 56ul in

  let _ = round4_op abcd x ia ib ic id 8ul 6ul 57ul in
  let _ = round4_op abcd x id ia ib ic 15ul 10ul 58ul in
  let _ = round4_op abcd x ic id ia ib 6ul 15ul 59ul in
  let _ = round4_op abcd x ib ic id ia 13ul 21ul 60ul in

  let _ = round4_op abcd x ia ib ic id 4ul 6ul 61ul in
  let _ = round4_op abcd x id ia ib ic 11ul 10ul 62ul in
  let _ = round4_op abcd x ic id ia ib 2ul 15ul 63ul in
  let _ = round4_op abcd x ib ic id ia 9ul 21ul 64ul in

  ()

inline_for_extraction
let rounds
  (abcd: abcd_t)
  (x: x_t)
: HST.Stack unit
  (requires (fun h ->
    B.live h abcd /\
    B.live h x /\
    B.loc_disjoint (B.loc_union (B.loc_buffer x) (B.loc_buffer abcd)) (static_fp ()) /\
    B.disjoint abcd x
  ))
  (ensures (fun h _ h' ->
    B.modifies (B.loc_buffer abcd) h h' /\
    B.live h' abcd /\
    B.live h' x /\
    B.as_seq h' abcd == Spec.rounds (B.as_seq h abcd) (E.seq_uint32_of_be 16 (B.as_seq h x))
  ))
=
  round1 abcd x;
  round2 abcd x;
  round3 abcd x;
  round4 abcd x;
  ()

inline_for_extraction
let overwrite
  (abcd:state MD5)
  (a' b' c' d' : U32.t)
: HST.Stack unit
    (requires (fun h ->
      B.live h abcd))
    (ensures (fun h0 _ h1 ->
      B.(modifies (loc_buffer abcd) h0 h1) /\
      B.live h1 abcd /\
      B.as_seq h1 abcd == Spec.overwrite (B.as_seq h0 abcd) a' b' c' d'))
= 
  B.upd abcd ia a';
  B.upd abcd ib b';
  B.upd abcd ic c';
  B.upd abcd id d'

#reset-options "--z3rlimit 64 --z3cliopt smt.arith.nl=false --using_facts_from '* -FStar.Int8 -FStar.Int16 -FStar.Int32 -FStar.Int64 -FStar.Int128 -FStar.UInt16 -FStar.UInt64 -FStar.UInt128'"

inline_for_extraction
let update'
  (abcd: abcd_t)
  (x: x_t)
: HST.Stack unit
    (requires (fun h ->
      B.loc_disjoint (B.loc_union (B.loc_buffer abcd) (B.loc_buffer x)) (static_fp ()) /\
      B.live h abcd /\ B.live h x /\ B.disjoint abcd x))
    (ensures (fun h0 _ h1 ->
      B.(modifies (loc_buffer abcd) h0 h1) /\
      B.live h1 abcd /\
      B.as_seq h1 abcd == Spec.update (B.as_seq h0 abcd) (B.as_seq h0 x)))
= 
  assert_norm (U32.v ia == Spec.ia);
  assert_norm (U32.v ib == Spec.ib);
  assert_norm (U32.v ic == Spec.ic);
  assert_norm (U32.v id == Spec.id);
  let aa = B.index abcd ia in
  let bb = B.index abcd ib in
  let cc = B.index abcd ic in
  let dd = B.index abcd id in
  rounds abcd x;
  let a = B.index abcd ia in
  let b = B.index abcd ib in
  let c = B.index abcd ic in
  let d = B.index abcd id in
  overwrite abcd
    (a `U32.add_mod` aa)
    (b `U32.add_mod` bb)
    (c `U32.add_mod` cc)
    (d `U32.add_mod` dd)

#reset-options

let update abcd x = update' abcd x
