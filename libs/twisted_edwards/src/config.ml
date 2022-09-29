open Core
open Hardcaml
open Signal
module Model = Twisted_edwards_model_lib

include struct
  open Elliptic_curve_lib
  module Config_presets = Config_presets
  module Ec_fpn_ops_config = Ec_fpn_ops_config
end

type fn = Ec_fpn_ops_config.fn =
  { latency : int
  ; impl : scope:Scope.t -> clock:t -> enable:t -> t -> t option -> t
  }

type t =
  { multiply : fn
  ; reduce : fn
  ; coarse_reduce : fn
  ; adder_stages : int
  ; subtractor_stages : int
  ; doubler_stages : int
  ; p : Z.t
  ; a : Z.t
  ; d : Z.t
  ; output_pipeline_stages : int
  ; arbitrated_multiplier : bool
  }

let coarse_reduce config ~scope ~clock ~enable x =
  print_s [%message "coarse_reduce"];
  config.coarse_reduce.impl ~scope ~clock ~enable x None
;;

let reduce config ~scope ~clock ~enable x =
  config.reduce.impl ~scope ~clock ~enable x None
;;

let multiply_latency ?(coarse_reduce = false) ~reduce (t : t) =
  if coarse_reduce then assert (not reduce);
  print_s [%message (t.reduce.latency : int) (t.coarse_reduce.latency : int)];
  let reduce_latency =
    if coarse_reduce
    then t.coarse_reduce.latency
    else if reduce
    then t.reduce.latency
    else 0
  in
  t.multiply.latency + reduce_latency
;;

module For_bls12_377 = struct
  let with_barrett_reduction_arbitrated : t Lazy.t =
    let open Config_presets.For_bls12_377 in
    let%map.Lazy { Model.Twisted_edwards_curve.a; d; _ } =
      Model.Bls12_377_params.twisted_edwards
    in
    { multiply
    ; reduce = barrett_reduce
    ; coarse_reduce = barrett_reduce_coarse
    ; adder_stages = 3
    ; subtractor_stages = 3
    ; doubler_stages = 3
    ; p = Ark_bls12_377_g1.modulus ()
    ; a
    ; d
    ; output_pipeline_stages = 1
    ; arbitrated_multiplier = true
    }
  ;;

  let with_barrett_reduction_full : t Lazy.t =
    let open Config_presets.For_bls12_377 in
    let%map.Lazy { Model.Twisted_edwards_curve.a; d; _ } =
      Model.Bls12_377_params.twisted_edwards
    in
    { multiply
    ; reduce = barrett_reduce
    ; coarse_reduce = barrett_reduce_coarse
    ; adder_stages = 3
    ; subtractor_stages = 3
    ; doubler_stages = 3
    ; p = Ark_bls12_377_g1.modulus ()
    ; a
    ; d
    ; output_pipeline_stages = 1
    ; arbitrated_multiplier = false
    }
  ;;
end
