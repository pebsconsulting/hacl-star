module Spec.HMAC

open FStar.Mul
open Lib.IntTypes
open Lib.Sequence
open Lib.ByteSequence

module H = Spec.Hash

val wrap_key:
    a: H.algorithm
  -> len: size_nat{len < H.max_input a}
  -> key: lbytes len ->
  Tot (lbytes (H.size_block a))

val init:
    a: H.algorithm
  -> key: lbytes (H.size_block a) ->
  Tot (H.state a)

val update_block:
    a: H.algorithm
  -> data: lbytes (H.size_block a)
  -> H.state a ->
  Tot (H.state a)

val update_last:
    a: H.algorithm
  -> prev: size_nat
  -> len: size_nat{len < Hash.size_block a /\ len + prev <= Hash.max_input a}
  -> last: lbytes len
  -> H.state a ->
  Tot (H.state a)

val finish:
    a: H.algorithm
  -> key: lbytes (H.size_block a)
  -> H.state a ->
  Tot (lbytes (H.size_hash a))

val hmac:
    a: H.algorithm
  -> klen: size_nat{klen < H.max_input a}
  -> key:lbytes klen
  -> len:size_nat{klen + len <= H.max_input a}
  -> input:lbytes len ->
  Tot (lbytes (H.size_hash a))
