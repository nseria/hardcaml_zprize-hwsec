open! Core

let command_test_pippenger name data =
  ( name
  , Command.basic
      ~summary:("Pippenger test: " ^ name)
      [%map_open.Command
        let waves = flag "-waves" no_arg ~doc:" show waveform"
        and verbose = flag "-verbose" no_arg ~doc:" show detailed results"
        and can_stall = flag "-stall" no_arg ~doc:" random input stalls"
        and seed = flag "-seed" (optional_with_default 100 int) ~doc:" random seed" in
        fun () ->
          let rand_state = Random.State.make [| seed |] in
          Random.set_state rand_state;
          let waves =
            Pippenger_test.Test_pippenger.(test ~waves ~can_stall ~verbose data)
          in
          Option.iter waves ~f:Hardcaml_waveterm_interactive.run] )
;;

let command_random =
  Command.basic
    ~summary:""
    [%map_open.Command
      let waves = flag "-waves" no_arg ~doc:" show waveform"
      and verbose = flag "-verbose" no_arg ~doc:" show detailed results"
      and can_stall = flag "-stall" no_arg ~doc:" random input stalls"
      and num_inputs = anon ("NUM_INPUTS" %: int)
      and window_size_bits =
        flag "-window-size-bits" (optional_with_default 4 int) ~doc:""
      and num_windows = flag "-num-windows" (optional_with_default 2 int) ~doc:""
      and affine_point_bits =
        flag "-affine-point-bits" (optional_with_default 16 int) ~doc:""
      and datapath_depth = flag "-datapath-depth" (optional_with_default 8 int) ~doc:""
      and seed = flag "-seed" (optional_with_default 100 int) ~doc:" random seed" in
      fun () ->
        let rand_state = Random.State.make [| seed |] in
        Random.set_state rand_state;
        let module Config = struct
          let window_size_bits = window_size_bits
          let num_windows = num_windows
          let affine_point_bits = affine_point_bits
          let datapath_depth = datapath_depth
          let pipeline_depth = 1 + ((datapath_depth + 1) / 2)
          let log_stall_fifo_depth = 2
        end
        in
        let module Test = Pippenger_test.Test_pippenger.Test (Config) in
        let data = Test.random_inputs num_inputs in
        let waves = Test.(test ~waves ~can_stall ~verbose data) in
        Option.iter waves ~f:Hardcaml_waveterm_interactive.run]
;;

let () =
  Command_unix.run
    (Command.group
       ~summary:"NTT controller simulation test case"
       Pippenger_test.Test_pippenger.
         [ command_test_pippenger "1-stall" test_1_stall
         ; command_test_pippenger "no-stalls" test_no_stalls
         ; command_test_pippenger "with-stalls" test_with_stalls
         ; command_test_pippenger "fully-stall-window0" test_fully_stall_window0
         ; "random", command_random
         ])
;;