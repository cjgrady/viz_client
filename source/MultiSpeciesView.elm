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


module MultiSpeciesView exposing (view)

import Html
import Html.Attributes
import Html.Events
import List.Extra as List
import Svg exposing (..)
import Svg.Attributes exposing (..)
import McpaModel exposing (..)
import LinearTreeView exposing (computeColor, drawTree, gradientDefinitions)


barGraph : ( Float, Float ) -> Html.Html Msg
barGraph ( observedValue, pValue ) =
    let
        height =
            (100 * abs observedValue |> toString) ++ "%"

        -- (1.0 - e ^ (-1.0 * abs observedValue) |> (*) 100 |> toString) ++ "%"
        opacity =
            1.0 - (pValue / 1.2)

        background =
            computeColor opacity observedValue
    in
        Html.div
            [ Html.Attributes.style
                [ ( "width", "100%" )
                , ( "height", height )
                , ( "position", "absolute" )
                , ( "bottom", "0" )
                , ( "background-color", background )
                , ( "z-index", "-1" )
                ]
            ]
            []


drawVariable : Bool -> (( Float, Float ) -> String) -> String -> ( Maybe Float, Maybe Float, Maybe Float ) -> Html.Html Msg
drawVariable showBarGraph formatter var ( observed, pValue, significant ) =
    let
        fontWeight =
            if significant |> Maybe.map ((<) 0.5) |> Maybe.withDefault False then
                ( "font-weight", "bold" )
            else
                ( "font-weight", "normal" )

        bar =
            if showBarGraph then
                Maybe.map2 (,) observed pValue |> Maybe.map (List.singleton << barGraph) |> Maybe.withDefault []
            else
                []

        values =
            Maybe.map2 (,) observed pValue
                |> Maybe.map formatter
                |> Maybe.withDefault ""
    in
        Html.td
            [ Html.Attributes.style [ ( "position", "relative" ), fontWeight ]
            , Html.Attributes.title (var ++ "\n" ++ values)
            ]
            bar



-- Html.tr []
--     [ Html.td [ Html.Attributes.style [ ( "text-align", "right" ), ( "padding-right", "12px" ) ] ]
--         [ Html.text values ]
--     , Html.td [ Html.Attributes.style [ ( "position", "relative" ), fontWeight ] ] (bar ++ [ Html.text var ])
--     ]


view :
    Model data
    -> Html.Html Msg
    -> Bool
    -> (( Float, Float ) -> String)
    -> List String
    -> (Int -> Maybe Float)
    -> (String -> ( Maybe Float, Maybe Float, Maybe Float ))
    -> Html.Html Msg
view { selectedVariable, showBranchLengths, treeInfo, selectedNode } tableHead showBarGraph variableFormatter vars selectData dataForVar =
    let
        computeColor_ opacity cladeId =
            selectData cladeId
                |> Maybe.map (computeColor opacity)
                |> Maybe.withDefault "#ccc"

        ( treeHeight, grads, treeSvg ) =
            drawTree
                { computeColor = computeColor_
                , showBranchLengths = showBranchLengths
                , treeDepth = treeInfo.depth
                , totalLength = treeInfo.length
                , selectedNode = selectedNode
                , selectNode = SelectNode
                }
                "#ccc"
                treeInfo.root

        gradDefs =
            gradientDefinitions grads

        select =
            String.toInt
                >> Result.toMaybe
                >> Maybe.andThen (\i -> List.getAt i vars)
                >> Maybe.withDefault ""
                >> SelectVariable

        variableSelector =
            Html.div [ Html.Attributes.style [ ( "margin-bottom", "8px" ) ] ]
                [ Html.span [] [ Html.text "Node color: " ]
                , Html.select [ Html.Events.onInput select, Html.Attributes.style [ ( "max-width", "355px" ) ] ]
                    (vars
                        |> List.indexedMap
                            (\i v ->
                                Html.option
                                    [ Html.Attributes.selected (v == selectedVariable)
                                    , Html.Attributes.value (toString i)
                                    ]
                                    [ Html.text v ]
                            )
                    )
                ]

        toggleBranchLengths =
            Html.div []
                [ Html.label []
                    [ Html.input
                        [ Html.Attributes.type_ "checkbox"
                        , Html.Attributes.checked showBranchLengths
                        , Html.Attributes.readonly True
                        , Html.Events.onClick ToggleShowLengths
                        ]
                        []
                    , Html.text "Show branch lengths"
                    ]
                ]

        ( envVars, bgVars ) =
            case List.findIndex ((==) "ENV - Adjusted R-squared") vars of
                Just i ->
                    List.splitAt (i + 1) vars

                Nothing ->
                    ( vars, [] )

        ( envVarTableRows, bgVarTableRows ) =
            case selectedNode of
                Just _ ->
                    ( envVars
                        |> List.map (\var -> dataForVar var |> drawVariable showBarGraph variableFormatter var)
                        |> Html.tr
                            [ Html.Attributes.style
                                [ ( "height", "400px" )
                                , ( "border-bottom", "1px solid" )
                                , ( "border-right", "1px solid" )
                                ]
                            ]
                    , bgVars
                        |> List.reverse
                        |> List.map (\var -> dataForVar var |> drawVariable showBarGraph variableFormatter var)
                        |> Html.tr
                            [ Html.Attributes.style
                                [ ( "height", "400px" )
                                , ( "border-bottom", "1px solid" )
                                , ( "border-left", "1px solid" )
                                ]
                            ]
                    )

                Nothing ->
                    ( Html.tr []
                        [ Html.td [ Html.Attributes.colspan 2, Html.Attributes.style [ ( "text-align", "center" ) ] ]
                            [ Html.text "No node selected." ]
                        ]
                    , Html.tr []
                        [ Html.td [ Html.Attributes.colspan 2, Html.Attributes.style [ ( "text-align", "center" ) ] ]
                            [ Html.text "No node selected." ]
                        ]
                    )
    in
        Html.div
            [ Html.Attributes.style
                [ ( "display", "flex" )
                  -- , ( "justify-content", "space-between" )
                , ( "font-family", "sans-serif" )
                , ( "height", "100vh" )
                ]
            ]
            [ Html.div
                [ Html.Attributes.style [ ( "display", "flex" ), ( "flex-direction", "column" ) ] ]
                [ Html.h3 [ Html.Attributes.style [ ( "text-align", "center" ), ( "text-decoration", "underline" ) ] ]
                    [ Html.text "Select nodes in tree" ]
                , Html.div
                    [ Html.Attributes.style
                        [ ( "display", "flex" )
                        , ( "justify-content", "space-between" )
                        , ( "flex-shrink", "0" )
                        ]
                    ]
                    [ variableSelector, toggleBranchLengths ]
                , Html.div [ Html.Attributes.style [ ( "margin-bottom", "20px" ), ( "overflow-y", "auto" ) ] ]
                    [ svg
                        [ width "600"
                        , height (15 * treeHeight |> toString)
                        , viewBox ("0 0 40 " ++ (toString treeHeight))
                        , Html.Attributes.style [ ( "background", "#000" ), ( "font-family", "sans-serif" ) ]
                          -- , Html.Events.onClick JumpUp
                        ]
                        -- (clickBox :: treeSvg)
                        (gradDefs :: treeSvg)
                    ]
                ]
            , Html.div
                [ Html.Attributes.style
                    [ ( "display", "flex" )
                    , ( "flex-direction", "column" )
                    , ( "flex-grow", "1" )
                    ]
                ]
                [ Html.div
                    [ Html.Attributes.style [ ( "flex-shrink", "0" ), ( "margin", "0 12px" ) ] ]
                    [ Html.h3 [ Html.Attributes.style [ ( "text-align", "center" ), ( "text-decoration", "underline" ) ] ]
                        [ Html.text "Subtree Left (blue) vs. Right (red) of selected node" ]
                    , Html.div
                        [ Html.Attributes.class "leaflet-map"
                        , Html.Attributes.attribute "data-map-column"
                            (selectedNode |> Maybe.map toString |> Maybe.withDefault "")
                        , Html.Attributes.style
                            [ ( "max-width", "900px" )
                            , ( "height", "500px" )
                            , ( "margin-left", "auto" )
                            , ( "margin-right", "auto" )
                            ]
                        ]
                        []
                    ]
                , Html.h3 [ Html.Attributes.style [ ( "text-align", "center" ), ( "text-decoration", "underline" ) ] ]
                    [ Html.text "Semipartial Correlations b/w Clade and Predictors" ]
                , Html.div [ Html.Attributes.style [ ( "width", "100%" ) ] ]
                    [ Html.div
                        [ Html.Attributes.style
                            [ ( "display", "flex" )
                            , ( "justify-content", "center" )
                            , ( "margin-top", "10px" )
                            , ( "margin-left", "auto" )
                            , ( "margin-right", "auto" )
                            , ( "max-width", "900px" )
                            ]
                        ]
                        [ Html.table
                            [ Html.Attributes.style
                                [ ( "width"
                                  , 100
                                        * toFloat (List.length envVars)
                                        / toFloat (List.length vars)
                                        |> toString
                                        |> flip (++) "%"
                                  )
                                ]
                            ]
                            [ envVarTableRows
                            , Html.tr []
                                [ Html.th [ Html.Attributes.colspan <| List.length envVars ]
                                    [ Html.text "Environmental Variables" ]
                                ]
                            ]
                        , Html.table
                            [ Html.Attributes.style
                                [ ( "width"
                                  , 100
                                        * toFloat (List.length bgVars)
                                        / toFloat (List.length vars)
                                        |> toString
                                        |> flip (++) "%"
                                  )
                                ]
                            ]
                            [ bgVarTableRows
                            , Html.tr []
                                [ Html.th
                                    [ Html.Attributes.colspan <| List.length bgVars
                                    ]
                                    [ Html.text "Biogeographic Hypotheses" ]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
