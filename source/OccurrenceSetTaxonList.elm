{-
   Copyright (C) 2018, University of Kansas Center for Research

   Lifemapper Project, lifemapper [at] ku [dot] edu,
   Biodiversity Institute,
   1345 Jayhawk Boulevard, Lawrence, Kansas, 66045, USA

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 2 of the License, or (at
   your option) any later version.

   This program is distributed in the hope that it will be useful, but
   WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software
   Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
   02110-1301, USA.
-}


module OccurrenceSetTaxonList exposing (Model, getTaxonIds, init, Msg, view, update)

import Http
import List.Extra as List
import Maybe.Extra exposing ((?))
import Material
import Material.Options as Options
import Material.Typography as Typo
import Material.Button as Button
import Material.Toggles as Toggles
import Material.Spinner as Loading
import Html exposing (Html)
import Html.Attributes as Attributes
import ProgramFlags exposing (Flags)
import Helpers exposing (Index, chain)
import Decoder
import Encoder


type alias Model =
    { state : State
    , programFlags : Flags
    }


type State
    = GetList (List String)
    | RequestingMatches
    | MatchingFailed
    | RequestingPoints
    | PointsRequestFailed
    | GotMatches (List Match)


type alias Match =
    { response : Decoder.GbifResponseItemRecord
    , searchName : String
    , use : Bool
    , count : Int
    }


getTaxonIds : Model -> List Int
getTaxonIds model =
    case model.state of
        GotMatches matches ->
            matches
                |> List.filter .use
                |> List.filterMap (.response >> .taxon_id)

        _ ->
            []


init : Flags -> Model
init flags =
    { state = GetList []
    , programFlags = flags
    }


type Msg
    = UpdateTaxonList String
    | CheckTaxa
    | GotMatchesMsg (List Match)
    | GotPointsMsg (List Match)
    | MatchingFailedMsg
    | GettingPointsFailedMsg
    | UpdateSearchName Int String
    | ToggleUseName Int
    | MatchAgain
    | StartOver


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UpdateTaxonList text ->
            case model.state of
                GetList names ->
                    let
                        names_ =
                            text |> String.split "\n" |> List.filter (not << String.isEmpty) |> List.unique
                    in
                        ( { model | state = GetList names_ }, Cmd.none )

                _ ->
                    model ! []

        CheckTaxa ->
            case model.state of
                GetList names ->
                    { model | state = RequestingMatches } ! [ checkTaxa model.programFlags [] names ]

                _ ->
                    model ! []

        GotMatchesMsg matches ->
            case model.state of
                RequestingMatches ->
                    { model | state = RequestingPoints } ! [ requestPoints model.programFlags matches ]

                _ ->
                    model ! []

        GotPointsMsg matches ->
            case model.state of
                RequestingPoints ->
                    { model | state = GotMatches matches } ! []

                _ ->
                    model ! []

        MatchingFailedMsg ->
            case model.state of
                RequestingMatches ->
                    { model | state = MatchingFailed } ! []

                _ ->
                    model ! []

        GettingPointsFailedMsg ->
            case model.state of
                RequestingPoints ->
                    { model | state = PointsRequestFailed } ! []

                _ ->
                    model ! []

        UpdateSearchName i name ->
            case model.state of
                GotMatches matches ->
                    let
                        matches_ =
                            matches
                                |> List.indexedMap
                                    (\j match ->
                                        if j == i then
                                            { match | searchName = name }
                                        else
                                            match
                                    )
                    in
                        { model | state = GotMatches matches_ } ! []

                _ ->
                    model ! []

        ToggleUseName i ->
            case model.state of
                GotMatches matches ->
                    let
                        matches_ =
                            matches
                                |> List.indexedMap
                                    (\j match ->
                                        if j == i then
                                            { match | use = not match.use }
                                        else
                                            match
                                    )
                    in
                        { model | state = GotMatches matches_ } ! []

                _ ->
                    model ! []

        MatchAgain ->
            case model.state of
                GotMatches matches ->
                    let
                        names =
                            matches
                                |> List.map (.searchName >> String.trim)
                                |> List.unique
                                |> List.filter (not << String.isEmpty)

                        dontUse =
                            matches
                                |> List.filterMap
                                    (\match ->
                                        if not match.use then
                                            match.response.accepted_name
                                        else
                                            Nothing
                                    )
                    in
                        { model | state = RequestingMatches } ! [ checkTaxa model.programFlags dontUse names ]

                _ ->
                    model ! []

        StartOver ->
            { model | state = GetList [] } ! []


checkTaxa : Flags -> List String -> List String -> Cmd Msg
checkTaxa flags dontUse names =
    Http.request
        { method = "POST"
        , headers = [ Http.header "Accept" "application/json" ]
        , url = flags.apiRoot ++ "gbifparser"
        , body = Http.jsonBody <| Encoder.encodeGbifPost <| Decoder.GbifPost names
        , expect = Http.expectJson Decoder.decodeGbifResponse
        , timeout = Nothing
        , withCredentials = False
        }
        |> Http.send (gotGbifResponse dontUse)


gotGbifResponse : List String -> Result Http.Error Decoder.GbifResponse -> Msg
gotGbifResponse dontUse response =
    case response of
        Ok (Decoder.GbifResponse items) ->
            items
                |> List.map
                    (\(Decoder.GbifResponseItem item) ->
                        { response = item
                        , searchName = item.search_name ? ""
                        , use =
                            case item.accepted_name of
                                Just name ->
                                    (not <| List.member name dontUse) && (Just name) == item.search_name

                                Nothing ->
                                    False
                        , count = 0
                        }
                    )
                |> GotMatchesMsg

        Err err ->
            MatchingFailedMsg


requestPoints : Flags -> List Match -> Cmd Msg
requestPoints flags matches =
    Http.request
        { method = "POST"
        , headers = [ Http.header "Accept" "application/json" ]
        , url = flags.apiRoot ++ "biotaphypoints"
        , body =
            matches
                |> List.filterMap (.response >> .taxon_id)
                |> Decoder.BiotaphyPointsPost
                |> Encoder.encodeBiotaphyPointsPost
                |> Http.jsonBody
        , expect = Http.expectJson Decoder.decodeBiotaphyPointsResponse
        , timeout = Nothing
        , withCredentials = False
        }
        |> Http.send (gotBiotaphyPointsResponse matches)


gotBiotaphyPointsResponse : List Match -> Result Http.Error Decoder.BiotaphyPointsResponse -> Msg
gotBiotaphyPointsResponse matches response =
    case response of
        Ok (Decoder.BiotaphyPointsResponse items) ->
            matches
                |> List.map
                    (\match ->
                        items
                            |> List.map (\(Decoder.BiotaphyPointsResponseItem item) -> item)
                            |> List.filter (\{ taxon_id } -> match.response.taxon_id == Just taxon_id)
                            |> List.head
                            |> Maybe.map (\{ count } -> { match | count = count, use = count > 30 })
                            |> Maybe.withDefault match
                    )
                |> GotPointsMsg

        Err err ->
            GettingPointsFailedMsg


view : (Material.Msg msg -> msg) -> (Msg -> msg) -> Index -> Material.Model -> Model -> Html msg
view mdlMsg mapMsg index mdl model =
    case model.state of
        GetList names ->
            Options.div []
                [ Options.styled Html.p [ Typo.title ] [ Html.text "Provide List of Species Names" ]
                , Options.styled Html.textarea
                    [ Options.attribute <|
                        Attributes.placeholder
                            ("Paste species names here, one per line. \n\n"
                                ++ "The names will be matched against the GBIF tree and \n"
                                ++ "the corresponding iDigBio occurrence points downloaded."
                            )
                    , Options.attribute <| Attributes.rows 20
                    , Options.attribute <| Attributes.cols 80
                    , Options.attribute <| Attributes.autocomplete False
                    , Options.attribute <| Attributes.spellcheck False
                    , Options.onInput (mapMsg << UpdateTaxonList)
                    ]
                    [ names |> String.join "\n" |> Html.text ]
                , Html.p []
                    [ Button.render mdlMsg
                        (1 :: index)
                        mdl
                        [ Button.raised
                        , Options.onClick <| mapMsg CheckTaxa
                        ]
                        [ Html.text "Match" ]
                    ]
                ]

        RequestingMatches ->
            Options.div []
                [ Options.styled Html.p [ Typo.title ] [ Html.text "Matching species names against GBIF..." ]
                , Loading.spinner [ Loading.active True ]
                ]

        RequestingPoints ->
            Options.div []
                [ Options.styled Html.p [ Typo.title ] [ Html.text "Requesting occurence points from iDigBio..." ]
                , Loading.spinner [ Loading.active True ]
                ]

        GotMatches matches ->
            Options.div []
                [ Options.styled Html.p [ Typo.title ] [ Html.text "GBIF species names match results:" ]
                , matches
                    |> List.indexedMap (viewMatch mdlMsg mapMsg (3 :: index) mdl)
                    |> (++)
                        [ Html.tr []
                            [ Html.th [] [ Html.text "Searched" ]
                            , Html.th [] [ Html.text "Matched" ]
                            , Html.th [] [ Html.text "Points" ]
                            , Html.th [ Attributes.style [ ( "padding-left", "5px" ) ] ] [ Html.text "Use" ]
                            ]
                        ]
                    |> Html.table []
                , Button.render mdlMsg
                    (1 :: index)
                    mdl
                    [ Button.raised
                    , Options.css "margin" "5px"
                    , Options.when (matches |> List.all (\match -> Just match.searchName == match.response.search_name))
                        Button.disabled
                    , Options.onClick <| mapMsg MatchAgain
                    ]
                    [ Html.text "Match again" ]
                , Button.render mdlMsg
                    (2 :: index)
                    mdl
                    [ Button.raised
                    , Options.css "margin" "5px"
                    , Options.onClick <| mapMsg StartOver
                    ]
                    [ Html.text "Start over" ]
                ]

        MatchingFailed ->
            Options.div []
                [ Options.styled Html.p
                    [ Typo.title ]
                    [ Html.text "There was a problem accessing the GBIF name matching API!" ]
                ]

        PointsRequestFailed ->
            Options.div []
                [ Options.styled Html.p
                    [ Typo.title ]
                    [ Html.text "There was a problem accessing the iDigBio points API!" ]
                ]


viewMatch : (Material.Msg msg -> msg) -> (Msg -> msg) -> Index -> Material.Model -> Int -> Match -> Html msg
viewMatch mdlMsg mapMsg index mdl i item =
    let
        checkbox =
            Toggles.checkbox mdlMsg
                (i :: index)
                mdl
                [ Options.onToggle <| mapMsg <| ToggleUseName i
                , Toggles.value item.use
                ]
                []

        nameUpdater =
            Options.styled Html.input
                [ Options.attribute <| Attributes.value <| item.searchName
                , Options.onInput (mapMsg << UpdateSearchName i)
                ]
                []
    in
        case item.response.accepted_name of
            Just name ->
                if item.response.search_name == Just name then
                    Html.tr []
                        [ Html.td [] [ Html.text <| item.response.search_name ? "" ]
                        , Html.td [] [ Html.text name ]
                        , Html.td [ Attributes.style [ ( "text-align", "right" ) ] ] [ Html.text <| toString item.count ]
                        , Html.td [ Attributes.style [ ( "padding-left", "5px" ) ] ] [ checkbox ]
                        ]
                else
                    Html.tr []
                        [ Html.td [] [ nameUpdater ]
                        , Html.td [] [ Html.text name ]
                        , Html.td [ Attributes.style [ ( "text-align", "right" ) ] ] [ Html.text <| toString item.count ]
                        , Html.td [ Attributes.style [ ( "padding-left", "5px" ) ] ] [ checkbox ]
                        ]

            Nothing ->
                Html.tr []
                    [ Html.td [] [ nameUpdater ]
                    , Html.td [] [ Html.text "⚠️ No match" ]
                    ]