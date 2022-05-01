(** Implementation of the karatsuba multiplication algorithm. Highly based on
    https://github.com/ZcashFoundation/zcash-fpga/blob/c4c0ad918898084c73528ca231d025e36740d40c/ip_cores/util/src/rtl/adder_pipe.sv

    See https://en.wikipedia.org/wiki/Karatsuba_algorithm for more details for
    the algorithm.

    The algorithm expresses the two numbers to be multiplied as:

    x = 2^(w/2) * x0 + x1
    y = 2^(w/2) * y0 + y1

    In every recursive step, B=2, and w = width of the inputs. It is required
    that width a = width b, and is an even number.

    Naively expanding the terms above yields the following:

    x * y = z0 * 2^(w)
            + z1 * 2^(w/2)
            + z2 

    where

    z0 = x0*y0
    z1 = x0*y1 + x1*y0
    z2 = x1*y1

    We can express z1 as follows: (Note that this is a slightly different
    formulation from those available in wikipedia)

    z1 = (x0 - x1)(y1 - y0) + x0*y0 + x1*y1
       = (x0 - x1)(y1 - y0) + z0 + z2

    These intermediate multiplication results will be refered to m{0,1,2}:

    m0 = z0
    m1 = (x0 - x1)(y1 - y0)
    m2 = z2

    The result of [x * y] can be computed by summing out the [m0, m1 and m2]
    terms as follows:

    m0 * 2^w
    + (m0 + m2 + m1) * 2^(w/2)
    + m2
*)

open Base
open Hardcaml
open Signal

let (<<) a b = sll a b 

let latency ~depth = 2 * depth + 1

type m_terms =
  { m0 : Signal.t
  ; m1 : Signal.t
  ; m2 : Signal.t
  }

let rec create_recursive ~clock ~enable ~level (a : Signal.t) (b : Signal.t) =
  let wa = width a in
  let wb = width b in
  if wa <> wb then (
    raise_s [%message
      "Width of [a] and [b] argument of karatsuba ofman multiplier mismatch"
        (wa : int)
        (wb : int)
    ]
  );
  assert (level >= 1);
  let spec = Reg_spec.create ~clock () in
  let reg x = reg spec ~enable x in
  let pipeline ~n x = pipeline ~enable spec x ~n in
  let w = width a in
  let hw = (w + 1) / 2 in
  let top_half x =
    if w % 2 = 0 then
      drop_bottom x hw
    else
      (* w is odd *)
      gnd @: drop_bottom x hw
  in
  let btm_half x = Signal.sel_bottom x hw in
  let a' = reg a in
  let b' = reg b in
  let sign =
    pipeline
      ~n:(2 * level)
      ((btm_half a <: top_half a) ^: (top_half b <: btm_half b))
  in
  let { m0; m1; m2 } =
    let a0 =
      mux2 (btm_half a >: top_half a)
        (btm_half a -: top_half a)
        (top_half a -: btm_half a)
      |> reg
    in
    let a1 =
      mux2 (top_half b >: btm_half b)
        (top_half b -: btm_half b)
        (btm_half b -: top_half b)
      |> reg
    in
    match level with
    | 1 ->
      let m0 = reg (top_half a' *: top_half b') in
      let m2 = reg (btm_half a' *: btm_half b') in
      let m1 = reg (a0 *: a1) in
      { m0; m1; m2 }
    | _ ->
      let recurse x y  = 
        create_recursive ~enable ~clock ~level:(level - 1) x y
      in
      let m0 = recurse (top_half a') (top_half b') in
      let m2 = recurse (btm_half a') (btm_half b') in
      let m1 = recurse a0 a1 in
      { m0; m1; m2 }
  in
  let m0 = uresize m0 (w * 2) in
  let m1 = uresize m1 (w * 2) in
  let m2 = uresize m2 (w * 2) in
  ((m0 << w)
   +: ((m0
        +: m2
        +: (mux2 sign (negate m1) m1))
       << hw)
   +: m2)
  |> reg
;;

let create ?(enable = vdd) ~depth ~clock a b : Signal.t =
  create_recursive ~level:depth ~enable ~clock a b
;;

module With_interface(M : sig
    val num_bits : int
    val depth : int
  end) = struct
  open M

  module I = struct
    type 'a t =
      { clock : 'a
      ; enable : 'a
      ; valid : 'a [@rtlname "in_valid"]
      ; a : 'a [@bits num_bits]
      ; b : 'a [@bits num_bits]
      }
    [@@deriving sexp_of, hardcaml]
  end

  module O = struct
    type 'a t =
      { c : 'a [@bits num_bits * 2]
      ; valid : 'a [@rtlname "out_valid"]
      }
    [@@deriving sexp_of, hardcaml]
  end

  let create (_ : Scope.t) { I. clock; enable; a; b; valid }  =
    { O.c = create ~clock ~enable ~depth a b
    ; valid =
        pipeline ~n:(latency ~depth) (Reg_spec.create ~clock ()) ~enable valid
    }
  ;;
end

