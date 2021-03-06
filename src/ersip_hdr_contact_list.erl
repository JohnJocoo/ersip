%%
%% Copyright (c) 2018 Dmitry Poroh
%% All rights reserved.
%% Distributed under the terms of the MIT License. See the LICENSE file.
%%
%% SIP Contact headers
%%

-module(ersip_hdr_contact_list).

-export([make/1,
         build/2,
         parse/1
        ]).

-export_type([contact_list/0]).

%%%===================================================================
%%% Types
%%%===================================================================

-type contact_list() :: star
                      | [ersip_hdr_contact:contact()].

-type parse_result() :: {ok, contact_list()}
                      | {error, term()}.

-type maybe_rev_contact_list() :: {ok, contact_list()}
                                | {error, term()}.

%%%===================================================================
%%% API
%%%===================================================================

-spec make(iolist() | binary()) -> contact_list().
make(Binary) ->
    H0 = ersip_hdr:new(<<"Contact">>),
    H1 = ersip_hdr:add_value(Binary, H0),
    case parse(H1) of
        {ok, ContactList} ->
            ContactList;
        {error, Reason} ->
            error(Reason)
    end.

-spec build(HeaderName :: binary(), contact_list()) -> ersip_hdr:header().
build(HdrName, star) ->
    Hdr = ersip_hdr:new(HdrName),
    ersip_hdr:add_value(<<"*">>, Hdr);
build(HdrName, ContactList) when is_list(ContactList) ->
    Hdr = ersip_hdr:new(HdrName),
    lists:foldl(
      fun(Contact, HdrAcc) ->
              ersip_hdr:add_value(ersip_hdr_contact:assemble(Contact), HdrAcc)
      end,
      Hdr,
      ContactList).


%% Contact        =  ("Contact" / "m" ) HCOLON
%%                   ( STAR / (contact-param *(COMMA contact-param)))
-spec parse(ersip_hdr:header()) -> parse_result().
parse(Header) ->
    MaybeRevContactList =
        lists:foldl(fun(IOContact, Acc) ->
                            add_to_maybe_contact_list(iolist_to_binary(IOContact), Acc)
                    end,
                    {ok, []},
                    ersip_hdr:raw_values(Header)),
    case MaybeRevContactList of
        {ok, star} ->
            {ok, star};
        {ok, RevContactList} ->
            {ok, lists:reverse(RevContactList)};
        Error ->
            Error
    end.

%%%===================================================================
%%% Internal implementation
%%%===================================================================

-spec add_to_maybe_contact_list(binary(), maybe_rev_contact_list()) -> maybe_rev_contact_list().
add_to_maybe_contact_list(_, {error, _} = Error) ->
    Error;
add_to_maybe_contact_list(<<"*">>, {ok, []}) ->
    {ok, star};
add_to_maybe_contact_list(_, {ok, star}) ->
    {error, {invalid_contact, <<"multiple contacts and star are invalid">>}};
add_to_maybe_contact_list(Bin, {ok, ConatactList}) when is_list(ConatactList) ->
    case ersip_hdr_contact:parse(Bin) of
        {ok, Contact} ->
            {ok, [Contact | ConatactList]};
        {error, _} = Error ->
            Error
    end.
