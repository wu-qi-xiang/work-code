#!/usr/bin/env escript
%% -*- erlang -*-
%%! -sname keysbackup -setcookie titan_ABCDEF123456 -kernel inetrc './inet_cfg'

-define(OM, 'titan1_ps3@servicer_3_1').
-define(BAK_FILE, "company.backup").

main([]) ->
    Spec = [{
        {company, '$1', '$11', '$12', '$2', '$3', '$13', '$14'}, 
        [], 
        [#{<<"comid">> => '$1', <<"rsa_pub">> =>'$2', <<"rsa_prv">> => '$3'}]
    }],
    Companies = rpc:call(?OM, ets, select, [company, Spec]),
    backup_json(Companies).

backup_json(Companies) ->
    Data = rpc:call(?OM, jiffy, encode, [Companies]),
    file:delete(?BAK_FILE),
    {ok, Fd} = file:open(?BAK_FILE, ['read', 'write']),
    ok = file:write(Fd, Data),
    file:close(Fd).
