%%
%% Copyright (c) 2017, 2018 Dmitry Poroh
%% All rights reserved.
%% Distributed under the terms of the MIT License. See the LICENSE file.
%%
%% Common SIP transaction interface
%%

-module(ersip_trans).
-export([new_server/2,
         new_client/2,
         event/2,
         id/1,
         server_id/1,
         client_id/1,
         client_id/2
        ]).

-export_type([trans/0,
              tid/0
             ]).

%%%===================================================================
%%% Types
%%%===================================================================

-record(trans,
        {id        :: ersip_trans:tid(),
         module   :: ersip_trans_client | ersip_trans_server,
         instance :: trans_instance()
        }).
-type trans() :: #trans{}.
-type trans_instance()  :: ersip_trans_client:trans_client()
                         | ersip_trans_server:trans_server().
-type tid() :: ersip_trans_id:transaction_id().
-type result() :: {trans(), ersip_trans_se:effect()}.
-type trans_event() :: event_timer()
                     | event_received()
                     | event_send().

%% Timer event (format is defined by specific transaction), here we
%% just pass this event to the appropriate module.
-type event_timer()    :: term().
%% Message matching transaction is received.
-type event_received() :: {received, ersip_sipmsg:sipmsg()}.
%% Message generated by transaction user is ready to send:
-type event_send()     :: {send, ersip_sipmsg:sipmsg()}.

%%%===================================================================
%%% API
%%%===================================================================

%%% @doc Create server transaction by message.
-spec new_server(ersip_sipmsg:sipmsg(), ersip:sip_options()) -> result().
new_server(SipMsg, Options) ->
    Id = server_id(SipMsg),
    INVITE = ersip_method:invite(),
    Module =
        case ersip_sipmsg:method(SipMsg) of
            INVITE ->
                ersip_trans_inv_server;
            _ ->
                ersip_trans_server
        end,
    {Instance, SE} = Module:new(transport_type_by_source(SipMsg), SipMsg, Options),
    Trans = #trans{id       = Id,
                   module   = Module,
                   instance = Instance
                  },
    {Trans, SE}.

-spec new_client(ersip_request:request(), ersip:sip_options()) -> result().
new_client(OutReq, Options) ->
    Id = client_id(OutReq),
    INVITE = ersip_method:invite(),
    Module =
        case ersip_sipmsg:method(ersip_request:sipmsg(OutReq)) of
            INVITE ->
                ersip_trans_inv_client;
            _ ->
                ersip_trans_client
        end,
    NexthopURI = ersip_request:nexthop(OutReq),
    Transport = ersip_transport:make_by_uri(NexthopURI),
    TransportType = transport_type_by_transport(Transport),
    {Instance, SE} = ersip_trans_client:new(TransportType, OutReq, Options),
    Trans = #trans{id = Id,
                   module = Module,
                   instance = Instance
                  },
    {Trans, SE}.

-spec event(trans_event(), trans()) -> result().
event(Event, #trans{instance = Instance} = Trans) ->
    {NewInstance, SE} = call_trans_module(event, Trans, [Event, Instance]),
    NewTrans = Trans#trans{instance = NewInstance},
    {NewTrans, SE}.

-spec id(trans()) -> tid().
id(#trans{id = Id}) ->
    Id.

%% @doc Create server transaction identifier by incoming request.
-spec server_id(ersip_sipmsg:sipmsg()) -> tid().
server_id(InSipMsg) ->
    ersip_trans_id:make_server(InSipMsg).

%% @doc Create client transaction identifier by filled outgoint
%% request.
-spec client_id(ersip_request:request()) -> tid().
client_id(OutReq) ->
    %% 17.1.3 Matching Responses to Client Transactions
    %%
    %% 1.  If the response has the same value of the branch parameter in
    %%     the top Via header field as the branch parameter in the top
    %%     Via header field of the request that created the transaction.
    %%
    %% 2.  If the method parameter in the CSeq header field matches the
    %%     method of the request that created the transaction.  The
    %%     method is needed since a CANCEL request constitutes a
    %%     different transaction, but shares the same value of the branch
    %%     parameter.
    CSeqHdr = ersip_sipmsg:get(cseq, ersip_request:sipmsg(OutReq)),
    Method = ersip_hdr_cseq:method(CSeqHdr),
    Branch = ersip_request:branch(OutReq),
    ersip_trans_id:make_client(Branch, Method).

%% @doc Create client transaction id by response and trimmed topmost
%% via
-spec client_id(ersip_hdr_via:via(), ersip_sipmsg:sipmsg()) -> tid().
client_id(RecvVia, SipMsg) ->
    CSeqHdr = ersip_sipmsg:get(cseq, SipMsg),
    Method = ersip_hdr_cseq:method(CSeqHdr),
    Branch = ersip_hdr_via:branch(RecvVia),
    ersip_trans_id:make_client(Branch, Method).

%%%===================================================================
%%% Internal implementation
%%%===================================================================

call_trans_module(FunId, #trans{module = Module}, Args) ->
    erlang:apply(Module, FunId, Args).

-spec transport_type_by_source(ersip_sipmsg:sipmsg()) -> reliable | unreliable.
transport_type_by_source(SipMsg) ->
    MsgSource = ersip_sipmsg:source(SipMsg),
    MsgTransport = ersip_source:transport(MsgSource),
    transport_type_by_transport(MsgTransport).

-spec transport_type_by_transport(ersip_transport:transport()) -> reliable | unreliable.
transport_type_by_transport(Transport) ->
    case ersip_transport:is_reliable(Transport) of
        true ->
            reliable;
        false ->
            unreliable
    end.

