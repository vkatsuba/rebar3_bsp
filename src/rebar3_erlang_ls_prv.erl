-module(rebar3_erlang_ls_prv).

-export([init/1, do/1, format_error/1]).

-define(PROVIDER, erlang_ls).
-define(DEPS, [compile]).
-define(AGENT, rebar_agent).

%% ===================================================================
%% Public API
%% ===================================================================
-spec init(rebar_state:t()) -> {ok, rebar_state:t()}.
init(State) ->
  Provider = providers:create([
                               {name, ?PROVIDER},
                               {module, ?MODULE},
                               {bare, true},
                               {deps, ?DEPS},
                               {example, "rebar3 erlang_ls"},
                               {opts, []},
                               {short_desc, "Erlang LS plugin for rebar3"},
                               {desc, "Interact with the Erlang LS Language Server"},
                               {profiles, [test]}
                              ]),
  {ok, rebar_state:add_provider(State, Provider)}.

-spec do(rebar_state:t()) -> {ok, rebar_state:t()} | {error, string()}.
do(State0) ->
  setup_name(State0),
  setup_paths(State0),
  State = inject_ct_hook(State0),
  start_agent(State),
  {ok, State}.

-spec format_error(any()) ->  iolist().
format_error(Reason) ->
  io_lib:format("~p", [Reason]).

-spec start_agent(rebar_state:t()) -> no_return().
start_agent(State) ->
  simulate_proc_lib(),
  true = register(?AGENT, self()),
  {ok, GenState} = rebar_agent:init(State),
  io:format("Erlang LS Agent Started.~n"),
  gen_server:enter_loop(rebar_agent, [], GenState, {local, ?AGENT}, hibernate).

-spec setup_name(rebar_state:t()) -> ok.
setup_name(State) ->
  {_Long, Short, Opts} = rebar_dist_utils:find_options(State),
  Name = case Short of
           undefined ->
             list_to_atom(filename:basename(rebar_state:dir(State)));
           N ->
             N
         end,
  rebar_dist_utils:short(Name, Opts),
  ok.

-spec setup_paths(rebar_state:t()) -> ok.
setup_paths(State) ->
  code:add_pathsa(rebar_state:code_paths(State, all_deps)),
  ok = add_test_paths(State).

-spec inject_ct_hook(rebar_state:t()) -> rebar_state:t().
inject_ct_hook(State) ->
  CTOpts0 = rebar_state:get(State, ct_opts, []),
  CTHooks0 = proplists:get_value(ct_hooks, CTOpts0, []),
  CTHooks = [rebar3_erlang_ls_ct_hook|CTHooks0],
  CTOpts = lists:keystore(ct_hooks, 1, CTOpts0, {ct_hooks, CTHooks}),
  rebar_state:set(State, ct_opts, CTOpts).

-spec simulate_proc_lib() -> ok.
simulate_proc_lib() ->
  FakeParent = spawn_link(fun() -> timer:sleep(infinity) end),
  put('$ancestors', [FakeParent]),
  put('$initial_call', {rebar_agent, init, 1}),
  ok.

%% TODO: Refactor
-spec add_test_paths(rebar_state:t()) -> ok.
add_test_paths(State) ->
  _ = [begin
         AppDir = rebar_app_info:out_dir(App),
         %% ignore errors resulting from non-existent directories
         _ = code:add_path(filename:join([AppDir, "test"]))
       end || App <- rebar_state:project_apps(State)],
  _ = code:add_path(filename:join([rebar_dir:base_dir(State), "test"])),
  ok.
