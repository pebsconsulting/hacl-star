module Hacl.Impl.PQ.Lib

open FStar.HyperStack.ST
open FStar.Mul

open LowStar.BufferOps
open LowStar.Modifies
open LowStar.ModifiesPat

open Lib.IntTypes
open Lib.PQ.Buffer

module B   = LowStar.Buffer
module HS  = FStar.HyperStack
module ST  = FStar.HyperStack.ST
module Seq = Lib.Sequence
module M   = Spec.Matrix

#reset-options "--z3rlimit 50 --max_fuel 0 --max_ifuel 0"

type elem = uint16

inline_for_extraction
let lbytes len = lbuffer uint8 (v len)

inline_for_extraction noextract unfold
let v = size_v

type matrix_t (n1:size_t) (n2:size_t{v n1 * v n2 < max_size_t}) =
  lbuffer elem (v n1 * v n2)

/// It's important to mark it as [unfold] for triggering patterns in [LowStar]
unfold
let as_matrix #n1 #n2 h (m:matrix_t n1 n2) : GTot (M.matrix (v n1) (v n2)) =
  B.as_seq h m

inline_for_extraction noextract
val matrix_create:
    n1:size_t
  -> n2:size_t{0 < v n1 * v n2 /\ v n1 * v n2 < max_size_t}
  -> StackInline (matrix_t n1 n2)
    (requires fun h0 -> True)
    (ensures  fun h0 a h1 ->
      B.alloc_post_common (HS.get_tip h0) (v n1 * v n2) a h0 h1 /\
      as_matrix h1 a == M.create (v n1) (v n2))
let matrix_create n1 n2 =
  create (n1 *. n2) (u16 0)

inline_for_extraction noextract
val mget:
    #n1:size_t
  -> #n2:size_t{v n1 * v n2 < max_size_t}
  -> a:matrix_t n1 n2
  -> i:size_t{v i < v n1}
  -> j:size_t{v j < v n2}
  -> Stack elem
    (requires fun h0 -> B.live h0 a)
    (ensures  fun h0 x h1 ->
      modifies loc_none h0 h1 /\
      x == M.mget (as_matrix h0 a) (v i) (v j))
let mget #n1 #n2 a i j =
  M.index_lt (v n1) (v n2) (v i) (v j);
  a.(i *. n2 +. j)

inline_for_extraction noextract
val mset:
    #n1:size_t
  -> #n2:size_t{v n1 * v n2 < max_size_t}
  -> a:matrix_t n1 n2
  -> i:size_t{v i < v n1}
  -> j:size_t{v j < v n2}
  -> x:elem
  -> Stack unit
    (requires fun h0 -> B.live h0 a)
    (ensures  fun h0 _ h1 ->
      modifies (loc_buffer a) h0 h1 /\
      B.live h1 a /\
      as_matrix h1 a == M.mset (as_matrix h0 a) (v i) (v j) x)
let mset #n1 #n2 a i j x =
  M.index_lt (v n1) (v n2) (v i) (v j);
  a.(i *. n2 +. j) <- x

noextract unfold
let op_String_Access #n1 #n2 (m:matrix_t n1 n2) (i, j) = mget m i j

noextract unfold
let op_String_Assignment #n1 #n2 (m:matrix_t n1 n2) (i, j) x = mset m i j x

unfold
let get #n1 #n2 h (m:matrix_t n1 n2) i j = M.mget (as_matrix h m) i j

private unfold
val map2_inner_inv:
    #n1:size_t
  -> #n2:size_t{v n1 * v n2 < max_size_t}
  -> h0:HS.mem
  -> h1:HS.mem
  -> h2:HS.mem
  -> f:(elem -> elem -> elem)
  -> a:matrix_t n1 n2
  -> b:matrix_t n1 n2
  -> c:matrix_t n1 n2
  -> i:size_t{v i < v n1}
  -> j:size_nat
  -> Type0
let map2_inner_inv #n1 #n2 h0 h1 h2 f a b c i j =
  B.live h2 a /\ B.live h2 b /\ B.live h2 c /\
  modifies (loc_buffer c) h1 h2 /\
  j <= v n2 /\
  (forall (i0:nat{i0 < v i}) (j:nat{j < v n2}). get h2 c i0 j == get h1 c i0 j) /\
  (forall (j0:nat{j0 < j}). get h2 c (v i) j0 == f (get h0 a (v i) j0) (get h2 b (v i) j0)) /\
  (forall (j0:nat{j <= j0 /\ j0 < v n2}). get h2 c (v i) j0 == get h0 c (v i) j0) /\
  (forall (i0:nat{v i < i0 /\ i0 < v n1}) (j:nat{j < v n2}). get h2 c i0 j == get h0 c i0 j)

inline_for_extraction noextract private
val map2_inner:
    #n1:size_t
  -> #n2:size_t{v n1 * v n2 < max_size_t}
  -> h0:HS.mem
  -> h1:HS.mem
  -> f:(elem -> elem -> elem)
  -> a:matrix_t n1 n2
  -> b:matrix_t n1 n2
  -> c:matrix_t n1 n2{a == c /\ B.disjoint b c}
  -> i:size_t{v i < v n1}
  -> j:size_t{v j < v n2}
  -> Stack unit
    (requires fun h2 -> map2_inner_inv h0 h1 h2 f a b c i (v j))
    (ensures  fun _ _ h2 -> map2_inner_inv h0 h1 h2 f a b c i (v j + 1))
let map2_inner #n1 #n2 h0 h1 f a b c i j =
  c.[i,j] <- f a.[i,j] b.[i,j]

/// In-place [map2], a == map2 f a b
///
/// A non in-place variant can be obtained by weakening the pre-condition to B.disjoint a c,
/// or the two variants can be merged by requiring (a == c \/ B.disjoint a c) instead of a == c
/// See commit 91916b8372fa3522061eff5a42d0ebd1d19a8a49
inline_for_extraction
val map2:
    #n1:size_t
  -> #n2:size_t{v n1 * v n2 < max_size_t}
  -> f:(uint16 -> uint16 -> uint16)
  -> a:matrix_t n1 n2
  -> b:matrix_t n1 n2
  -> c:matrix_t n1 n2
  -> Stack unit
    (requires fun h0 ->
      B.live h0 a /\ B.live h0 b /\ B.live h0 c /\ a == c /\ B.disjoint b c)
    (ensures  fun h0 _ h1 ->
      modifies (loc_buffer c) h0 h1 /\
      as_matrix h1 c == M.map2 #(v n1) #(v n2) f (as_matrix h0 a) (as_matrix h0 b))
let map2 #n1 #n2 f a b c =
  let h0 = ST.get () in
  Lib.Loops.for (size 0) n1
    (fun h1 i -> B.live h1 a /\ B.live h1 b /\ B.live h1 c /\
      modifies (loc_buffer c) h0 h1 /\ i <= v n1 /\
      (forall (i0:nat{i0 < i}) (j:nat{j < v n2}).
        get h1 c i0 j == f (get h0 a i0 j) (get h0 b i0 j)) /\
      (forall (i0:nat{i <= i0 /\ i0 < v n1}) (j:nat{j < v n2}).
        get h1 c i0 j == get h0 c i0 j) )
    (fun i ->
      let h1 = ST.get() in
      Lib.Loops.for (size 0) n2
        (fun h2 j -> map2_inner_inv h0 h1 h2 f a b c i j)
        (fun j -> map2_inner h0 h1 f a b c i j)
    );
    let h2 = ST.get() in
    M.extensionality (as_matrix h2 c) (M.map2 f (as_matrix h0 a) (as_matrix h0 b))

inline_for_extraction
val matrix_add:
    #n1:size_t
  -> #n2:size_t{v n1 * v n2 < max_size_t}
  -> a:matrix_t n1 n2
  -> b:matrix_t n1 n2
  -> Stack unit
    (requires fun h -> B.live h a /\ B.live h b /\ B.disjoint a b)
    (ensures  fun h0 r h1 -> B.live h1 a /\ modifies (loc_buffer a) h0 h1 /\
      as_matrix h1 a == M.add (as_matrix h0 a) (as_matrix h0 b))
[@"c_inline"]
let matrix_add #n1 #n2 a b =
  map2 add_mod a b a

inline_for_extraction
val matrix_sub:
    #n1:size_t
  -> #n2:size_t{v n1 * v n2 < max_size_t}
  -> a:matrix_t n1 n2
  -> b:matrix_t n1 n2
  -> Stack unit
    (requires fun h -> B.live h a /\ B.live h b /\ B.disjoint a b)
    (ensures  fun h0 r h1 -> B.live h1 b /\ modifies (loc_buffer b) h0 h1 /\
      as_matrix h1 b == M.sub (as_matrix h0 a) (as_matrix h0 b))
[@"c_inline"]
let matrix_sub #n1 #n2 a b =
  (* Use the in-place variant above by flipping the arguments of [sub_mod] *)
  (* Requires appplying extensionality *)
  let h0 = ST.get() in
  [@ inline_let ]
  let sub_mod_flipped x y = sub_mod y x in
  map2 sub_mod_flipped b a b;
  let h1 = ST.get() in
  M.extensionality (as_matrix h1 b) (M.sub (as_matrix h0 a) (as_matrix h0 b))

#reset-options "--z3rlimit 50 --max_fuel 1 --max_ifuel 0"

inline_for_extraction noextract private
val mul_inner:
    #n1:size_t
  -> #n2:size_t{v n1 * v n2 < max_size_t}
  -> #n3:size_t{v n2 * v n3 < max_size_t /\ v n1 * v n3 < max_size_t}
  -> a:matrix_t n1 n2
  -> b:matrix_t n2 n3
  -> i:size_t{v i < v n1}
  -> k:size_t{v k < v n3}
  -> Stack uint16
    (requires fun h -> B.live h a /\ B.live h b)
    (ensures  fun h0 r h1 ->
      modifies loc_none h0 h1 /\
      r == M.mul_inner (as_matrix h0 a) (as_matrix h0 b) (v i) (v k))
let mul_inner #n1 #n2 #n3 a b i k =
  push_frame();
  let h0 = ST.get() in
  [@ inline_let ]
  let f l = get h0 a (v i) l *. get h0 b l (v k) in
  let res = create #uint16 #1 (size 1) (u16 0) in

  let h1 = ST.get() in
  Lib.Loops.for (size 0) n2
    (fun h2 j -> B.live h1 res /\ B.live h2 res /\
      modifies (loc_buffer res) h1 h2 /\
      B.get h2 res 0 == M.sum_ #(v n2) f j)
    (fun j ->
      let aij = a.[i,j] in
      let bjk = b.[j,k] in
      let res0 = !*res in
      res *= (res0 +. aij *. bjk)
    );
  let res = !*res in
  M.sum_extensionality (v n2) f (fun l -> get h0 a (v i) l *. get h0 b l (v k)) (v n2);
  assert (res == M.mul_inner (as_matrix h0 a) (as_matrix h0 b) (v i) (v k));
  pop_frame();
  res

#reset-options "--z3rlimit 50 --max_fuel 0 --max_ifuel 0"

private unfold
val mul_inner_inv:
    #n1:size_t
  -> #n2:size_t{v n1 * v n2 < max_size_t}
  -> #n3:size_t{v n2 * v n3 < max_size_t /\ v n1 * v n3 < max_size_t}
  -> h0:HS.mem
  -> h1:HS.mem
  -> h2:HS.mem
  -> a:matrix_t n1 n2
  -> b:matrix_t n2 n3
  -> c:matrix_t n1 n3
  -> f:(k:nat{k < v n3} -> GTot uint16)
  -> i:size_t{v i < v n1}
  -> k:size_nat
  -> Type0
let mul_inner_inv #n1 #n2 #n3 h0 h1 h2 a b c f i k =
  B.live h2 a /\ B.live h2 b /\ B.live h2 c /\
  modifies (loc_buffer c) h1 h2 /\
  k <= v n3 /\
  (forall (i1:nat{i1 < v i}) (k:nat{k < v n3}). get h2 c i1 k == get h1 c i1 k) /\
  (forall (k1:nat{k1 < k}). get h2 c (v i) k1 == f k1) /\
  (forall (k1:nat{k <= k1 /\ k1 < v n3}). get h2 c (v i) k1 == get h0 c (v i) k1) /\
  (forall (i1:nat{v i < i1 /\ i1 < v n1}) (k:nat{k < v n3}). get h2 c i1 k == get h0 c i1 k) /\
  as_matrix h0 a == as_matrix h2 a /\
  as_matrix h0 b == as_matrix h2 b

inline_for_extraction noextract private
val mul_inner1:
    #n1:size_t
  -> #n2:size_t{v n1 * v n2 < max_size_t}
  -> #n3:size_t{v n2 * v n3 < max_size_t /\ v n1 * v n3 < max_size_t}
  -> h0:HS.mem
  -> h1:HS.mem
  -> a:matrix_t n1 n2
  -> b:matrix_t n2 n3
  -> c:matrix_t n1 n3{B.disjoint a c /\ B.disjoint b c}
  -> i:size_t{v i < v n1}
  -> k:size_t{v k < v n3}
  -> f:(k:nat{k < v n3}
       -> GTot (res:uint16{res == M.sum #(v n2) (fun l -> get h0 a (v i) l *. get h0 b l k)}))
  -> Stack unit
    (requires fun h2 -> mul_inner_inv h0 h1 h2 a b c f i (v k))
    (ensures  fun _ _ h2 -> mul_inner_inv h0 h1 h2 a b c f i (v k + 1))
let mul_inner1 #n1 #n2 #n3 h0 h1 a b c i k f =
  assert (M.mul_inner (as_matrix h0 a) (as_matrix h0 b) (v i) (v k) ==
          M.sum #(v n2) (fun l -> get h0 a (v i) l *. get h0 b l (v k)));
  c.[i,k] <- mul_inner a b i k;
  let h2 = ST.get () in
  assert (get h2 c (v i) (v k) == f (v k))

private
val onemore: p:(nat -> Type0) -> q:(i:nat{p i} -> Type0) -> b:nat{p b} -> Lemma
  (requires (forall (i:nat{p i /\ i < b}). q i) /\ q b)
  (ensures  forall (i:nat{p i /\ i <= b}). q i)
let onemore p q b = ()

val matrix_mul:
    #n1:size_t
  -> #n2:size_t{v n1 * v n2 < max_size_t}
  -> #n3:size_t{v n2 * v n3 < max_size_t /\ v n1 * v n3 < max_size_t}
  -> a:matrix_t n1 n2
  -> b:matrix_t n2 n3
  -> c:matrix_t n1 n3
  -> Stack unit
    (requires fun h ->
      B.live h a /\ B.live h b /\ B.live h c /\ B.disjoint a c /\ B.disjoint b c)
    (ensures  fun h0 _ h1 ->
      B.live h1 c /\
      modifies (loc_buffer c) h0 h1 /\
      as_matrix h1 c == M.mul (as_matrix h0 a) (as_matrix h0 b))
[@"c_inline"]
let matrix_mul #n1 #n2 #n3 a b c =
  let h0 = ST.get () in
  let f (i:nat{i < v n1}) (k:nat{k < v n3}) :
    GTot (res:uint16{res == M.sum #(v n2) (fun l -> get h0 a i l *. get h0 b l k)})
  = M.sum #(v n2) (fun l -> get h0 a i l *. get h0 b l k)
  in
  Lib.Loops.for (size 0) n1
    (fun h1 i ->
      B.live h1 a /\ B.live h1 b /\ B.live h1 c /\
      modifies (loc_buffer c) h0 h1 /\ i <= v n1 /\
      (forall (i1:nat{i1 < i}) (k:nat{k < v n3}). get h1 c i1 k == f i1 k) /\
      (forall (i1:nat{i <= i1 /\ i1 < v n1}) (k:nat{k < v n3}). get h1 c i1 k == get h0 c i1 k))
    (fun i ->
      let h1 = ST.get() in
      Lib.Loops.for (size 0) n3
        (fun h2 k -> mul_inner_inv h0 h1 h2 a b c (f (v i)) i k)
        (fun k -> mul_inner1 h0 h1 a b c i k (f (v i)));
      let h1 = ST.get() in
      let q i1 = forall k. get h1 c i1 k == f i1 k in
      onemore (fun i1 -> i1 < v n1) q (v i)
    );
  let h2 = ST.get() in
  M.extensionality (as_matrix h2 c) (M.mul (as_matrix h0 a) (as_matrix h0 b))


val eq_u32_m:m:uint32 -> a:uint32 -> b:uint32 -> Tot bool
[@ "substitute"]
let eq_u32_m m a b =
  let open Lib.RawIntTypes in
  let open FStar.UInt32 in
  u32_to_UInt32 (a &. m) =^ u32_to_UInt32 (b &. m)

val matrix_eq:
    #n1:size_t
  -> #n2:size_t{v n1 * v n2 < max_size_t}
  -> m:size_t{0 < v m /\ v m <= 16}
  -> a:matrix_t n1 n2
  -> b:matrix_t n1 n2
  -> Stack bool
    (requires fun h -> B.live h a /\ B.live h b)
    (ensures  fun h0 r h1 -> modifies loc_none h0 h1)
[@"c_inline"]
let matrix_eq #n1 #n2 m a b =
  push_frame();
  let m = (u32 1 <<. size_to_uint32 m) -. u32 1 in
  let res = create #bool #1 (size 1) true in
  let h0 = ST.get() in
  loop_nospec #h0 #bool #1 n1 res
  (fun i ->
    let h1 = ST.get() in
    loop_nospec #h1 #bool #1 n2 res
    (fun j ->
      let a1 = !*res in
      let a2 = eq_u32_m m (to_u32 (mget a i j)) (to_u32 (mget b i j)) in
      res *= (a1 && a2)
    )
  );
  let res = !*res in
  pop_frame();
  res