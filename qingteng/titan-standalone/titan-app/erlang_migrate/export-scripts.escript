#!/usr/bin/env escript
%% -*- erlang -*-
%%! -sname keysbackup -setcookie titan_ABCDEF123456 -kernel inetrc './inet_cfg'

-define(OM, 'titan1_ps3@servicer_3_1').
-define(BAK_DIR, "./scripts").
-define(SCRIPT_DIR, "/data/app/titan-servers/etc/script").
-define(KEY, [37,7,216,253,151,250,57,1,26,111,159,173,48,233,202,94,
              213,141,222,12,2,233,113,24,30,21,230,44,245,164,125,20,
              70,178,124,253,63,62,124,216,94,176,179,178,201,95,59,
              140,64,58,133,57,195,250,114,73,153,203,135,115,255,11,
              49,192]).

main([]) ->
    filelib:ensure_dir(?BAK_DIR ++ "/"),
    write_script(all_files()),
    ok.

all_files() ->
    filelib:wildcard(?SCRIPT_DIR ++ "/*.{lua,sh,data,config}").

write_script([Filename | Rest]) ->
    Name = filename:basename(Filename),
    {ok, Bin} = file:read_file(Filename),
    file:write_file(?BAK_DIR ++ "/" ++ Name, decrypt_data(Bin)),
    write_script(Rest);
write_script([])->
    ok.

decrypt_data(<<$E:8, N:8, Type:N/binary, _R/binary>> = Data)
    when Type =:= <<"des3_cbc">> ->
    case rpc:call(?OM, sym_lib, decrypt_data, [Data, ?KEY]) of
        {badrpc, _E} -> 
            exit(badrpc);
        Content ->
            Content
    end;
decrypt_data(Data) ->
    Data.