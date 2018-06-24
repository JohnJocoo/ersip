%%
%% Copyright (c) 2018 Dmitry Poroh
%% All rights reserved.
%% Distributed under the terms of the MIT License. See the LICENSE file.
%%
%% SIP Registrar Binding
%%
%% Represents one saved binding for AOR
%%

-module(ersip_registrar_binding).

-export([new/4,
         contact_key/1,
         callid_cseq/1,
         update_expiration/2
        ]).
-export_type([binding/0]).

%%%===================================================================
%%% Types
%%%===================================================================

-record(binding, {contact :: ersip_hdr_contact:contact(),
                  callid  :: ersip_hdr_callid:callid(),
                  cseq    :: ersip_hdr_cseq:cseq_num(),
                  expires :: non_neg_integer()
                 }).
-type binding() :: #binding{}.

%%%===================================================================
%%% API
%%%===================================================================

-spec new(ersip_hdr_callid:callid(), ersip_hdr_cseq:cseq_num(), ersip_hdr_contact:contact(), non_neg_integer()) -> binding().
new(CallId, CSeqNum, Contact, Exp) ->
    #binding{contact = Contact,
             callid  = CallId,
             cseq    = CSeqNum,
             expires = Exp}.

-spec contact_key(binding()) -> ersip_uri:uri().
contact_key(#binding{contact = Contact}) ->
    ContactURI = ersip_hdr_contact:uri(Contact),
    ersip_uri:make_key(ContactURI).

-spec callid_cseq(binding()) -> {ersip_hdr_callid:callid(), ersip_hdr_cseq:cseq_num()}.
callid_cseq(#binding{callid = CallId, cseq = CSeq}) ->
    {CallId, CSeq}.

-spec update_expiration(NewExpiration :: pos_integer(), binding()) -> binding().
update_expiration(NewExpiration, #binding{} = Binding) when is_integer(NewExpiration)
                                                            andalso NewExpiration > 0 ->
    Binding#binding{expires = NewExpiration}.
