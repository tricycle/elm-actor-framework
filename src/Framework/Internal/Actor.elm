module Framework.Internal.Actor exposing
    ( Actor
    , Component
    , Process
    , ProcessMethods
    , altInit
    , altSubscriptions
    , altUpdate
    , altView
    , fromComponent
    )

import Framework.Internal.Message as Message exposing (FrameworkMessage)
import Framework.Internal.Pid exposing (Pid)


type alias Arguments appFlags appAddresses appActors appModel appMsg componentModel componentMsgIn componentMsgOut =
    { toAppModel : componentModel -> appModel
    , toAppMsg : componentMsgIn -> appMsg
    , fromAppMsg : appMsg -> Maybe componentMsgIn
    , onMsgOut :
        { self : Pid
        , msgOut : componentMsgOut
        }
        -> FrameworkMessage appFlags appAddresses appActors appModel appMsg
    }


type ProcessMethods componentModel appModel output frameworkMsg
    = ProcessMethods
        { update : componentModel -> frameworkMsg -> Pid -> ( appModel, frameworkMsg )
        , subscriptions : componentModel -> Pid -> Sub frameworkMsg
        , view : componentModel -> Pid -> (Pid -> Maybe output) -> output
        }


type alias Actor appFlags componentModel appModel output frameworkMsg =
    { processMethods : ProcessMethods componentModel appModel output frameworkMsg
    , init : ( Pid, appFlags ) -> ( appModel, frameworkMsg )
    , apply : componentModel -> Process appModel output frameworkMsg
    }


type alias Process appModel output frameworkMsg =
    { update : frameworkMsg -> Pid -> ( appModel, frameworkMsg )
    , subscriptions : Pid -> Sub frameworkMsg
    , view : Pid -> (Pid -> Maybe output) -> output
    }


type alias Component appFlags componentModel componentMsgIn componentMsgOut output frameworkMsg =
    { init :
        ( Pid, appFlags )
        -> ( componentModel, List componentMsgOut, Cmd componentMsgIn )
    , update :
        componentMsgIn
        -> componentModel
        -> ( componentModel, List componentMsgOut, Cmd componentMsgIn )
    , subscriptions :
        componentModel
        -> Sub componentMsgIn
    , view :
        (componentMsgIn -> frameworkMsg)
        -> componentModel
        -> (Pid -> Maybe output)
        -> output
    }


altInit :
    ((( Pid, a ) -> ( componentModel, List componentMsgOut, Cmd componentMsgIn ))
     -> ( Pid, appFlags )
     -> ( componentModel, List componentMsgOut, Cmd componentMsgIn )
    )
    -> Component a componentModel componentMsgIn componentMsgOut output frameworkMsg
    -> Component appFlags componentModel componentMsgIn componentMsgOut output frameworkMsg
altInit f { init, update, subscriptions, view } =
    { init = f init
    , update = update
    , subscriptions = subscriptions
    , view = view
    }


altUpdate :
    ((componentMsgIn -> componentModel -> ( componentModel, List componentMsgOut, Cmd componentMsgIn ))
     -> componentMsgIn
     -> componentModel
     -> ( componentModel, List componentMsgOut, Cmd componentMsgIn )
    )
    -> Component appFlags componentModel componentMsgIn componentMsgOut output frameworkMsg
    -> Component appFlags componentModel componentMsgIn componentMsgOut output frameworkMsg
altUpdate f { init, update, subscriptions, view } =
    { init = init
    , update = f update
    , subscriptions = subscriptions
    , view = view
    }


altSubscriptions :
    ((componentModel -> Sub componentMsgIn)
     -> componentModel
     -> Sub componentMsgIn
    )
    -> Component appFlags componentModel componentMsgIn componentMsgOut output frameworkMsg
    -> Component appFlags componentModel componentMsgIn componentMsgOut output frameworkMsg
altSubscriptions f { init, update, subscriptions, view } =
    { init = init
    , update = update
    , subscriptions = f subscriptions
    , view = view
    }


altView :
    (((componentMsgIn -> frameworkMsg) -> componentModel -> (Pid -> Maybe outputA) -> outputA)
     -> ((componentMsgIn -> frameworkMsg) -> componentModel -> (Pid -> Maybe outputB) -> outputB)
    )
    -> Component appFlags componentModel componentMsgIn componentMsgOut outputA frameworkMsg
    -> Component appFlags componentModel componentMsgIn componentMsgOut outputB frameworkMsg
altView f { init, update, subscriptions, view } =
    { init = init
    , update = update
    , subscriptions = subscriptions
    , view = f view
    }


fromComponent :
    { toAppModel : componentModel -> appModel
    , toAppMsg : componentMsgIn -> appMsg
    , fromAppMsg : appMsg -> Maybe componentMsgIn
    , onMsgOut :
        { self : Pid
        , msgOut : componentMsgOut
        }
        -> FrameworkMessage appFlags appAddresses appActors appModel appMsg
    }
    -> Component appFlags componentModel componentMsgIn componentMsgOut output (FrameworkMessage appFlags appAddresses appActors appModel appMsg)
    -> Actor appFlags componentModel appModel output (FrameworkMessage appFlags appAddresses appActors appModel appMsg)
fromComponent arguments component =
    let
        init =
            fromComponentInit arguments component.init

        update =
            fromComponentUpdate arguments component.update

        subscriptions =
            fromComponentSubscriptions arguments component.subscriptions

        view =
            fromComponentView arguments component.view

        apply componentModel =
            { update = update componentModel
            , view = view componentModel
            , subscriptions = subscriptions componentModel
            }

        processMethods =
            ProcessMethods
                { update = update
                , subscriptions = subscriptions
                , view = view
                }
    in
    { processMethods = processMethods
    , init = init
    , apply = apply
    }


fromComponentView :
    Arguments appFlags appAddresses appActors appModel appMsg componentModel componentMsgIn componentMsgOut
    ->
        ((componentMsgIn -> FrameworkMessage appFlags appAddresses appActors appModel appMsg)
         -> componentModel
         -> (Pid -> Maybe output)
         -> output
        )
    -> componentModel
    -> Pid
    -> (Pid -> Maybe output)
    -> output
fromComponentView { toAppMsg } view componentModel pid =
    view (Message.toSelf toAppMsg pid) componentModel


fromComponentInit :
    Arguments appFlags appAddresses appActors appModel appMsg componentModel componentMsgIn componentMsgOut
    ->
        (( Pid, appFlags )
         -> ( componentModel, List componentMsgOut, Cmd componentMsgIn )
        )
    -> ( Pid, appFlags )
    -> ( appModel, FrameworkMessage appFlags appAddresses appActors appModel appMsg )
fromComponentInit arguments init ( pid, appFlags ) =
    init ( pid, appFlags )
        |> wrapToTuple arguments pid


fromComponentUpdate :
    Arguments appFlags appAddresses appActors appModel appMsg componentModel componentMsgIn componentMsgOut
    ->
        (componentMsgIn
         -> componentModel
         -> ( componentModel, List componentMsgOut, Cmd componentMsgIn )
        )
    -> componentModel
    -> FrameworkMessage appFlags appAddresses appActors appModel appMsg
    -> Pid
    -> ( appModel, FrameworkMessage appFlags appAddresses appActors appModel appMsg )
fromComponentUpdate arguments update componentModel msg pid =
    case msg of
        Message.AppMsg appMsg ->
            case arguments.fromAppMsg appMsg of
                Just componentMsgIn ->
                    update componentMsgIn componentModel
                        |> wrapToTuple arguments pid

                Nothing ->
                    ( arguments.toAppModel componentModel, Message.noOperation )

        _ ->
            ( arguments.toAppModel componentModel, Message.noOperation )


fromComponentSubscriptions :
    Arguments appFlags appAddresses appActors appModel appMsg componentModel componentMsgIn componentMsgOut
    -> (componentModel -> Sub componentMsgIn)
    -> componentModel
    -> Pid
    -> Sub (FrameworkMessage appFlags appAddresses appActors appModel appMsg)
fromComponentSubscriptions { toAppMsg } subs componentModel pid =
    if subs componentModel == Sub.none then
        Sub.none

    else
        Sub.map
            (Message.toSelf toAppMsg pid)
            (subs componentModel)


wrapToTuple :
    Arguments appFlags appAddresses appActors appModel appMsg componentModel componentMsgIn componentMsgOut
    -> Pid
    -> ( componentModel, List componentMsgOut, Cmd componentMsgIn )
    -> ( appModel, FrameworkMessage appFlags appAddresses appActors appModel appMsg )
wrapToTuple { toAppModel, toAppMsg, onMsgOut } pid ( model, msgsOut, cmd ) =
    msgsOut
        |> List.map
            (\msgOut ->
                onMsgOut
                    { self = pid
                    , msgOut = msgOut
                    }
            )
        |> List.append
            (if cmd == Cmd.none then
                []

             else
                [ Cmd.map (Message.toSelf toAppMsg pid) cmd
                    |> Message.command
                    |> Message.operate
                ]
            )
        |> Message.batch
        |> Message.inContextOfPid pid
        |> Tuple.pair (toAppModel model)
