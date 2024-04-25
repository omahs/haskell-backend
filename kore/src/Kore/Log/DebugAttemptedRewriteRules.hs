{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE NoStrict #-}
{-# LANGUAGE NoStrictData #-}

{- |
Copyright   : (c) Runtime Verification, 2020-2021
License     : BSD-3-Clause
-}
module Kore.Log.DebugAttemptedRewriteRules (
    DebugAttemptedRewriteRules (..),
    debugAttemptedRewriteRule,
    whileDebugAttemptRewriteRule,
) where

import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import Kore.Attribute.Axiom (
    SourceLocation,
    UniqueId (..),
 )
import Kore.Internal.Conditional qualified as Conditional
import Kore.Internal.Pattern (
    Pattern,
 )
import Kore.Internal.TermLike qualified as TermLike
import Kore.Internal.Variable (
    VariableName,
    toVariableName,
 )
import Kore.Rewrite.RewritingVariable
import Kore.Unparser
import Log
import Numeric (showHex)
import Prelude.Kore
import Pretty (
    Pretty (..),
 )
import Pretty qualified

data DebugAttemptedRewriteRules = DebugAttemptedRewriteRules
    { configuration :: !(Pattern VariableName)
    , ruleId :: !UniqueId
    , label :: !(Maybe Text)
    , attemptedRewriteRule :: !SourceLocation
    }
    deriving stock (Show)

instance Pretty DebugAttemptedRewriteRules where
    pretty DebugAttemptedRewriteRules{..} =
        Pretty.vsep
            [ (Pretty.hsep . catMaybes)
                [ Just "The rule"
                , (\l -> Pretty.hsep ["with label:", "[", pretty l, "]"]) <$> label
                , Just "at the following location was attempted:"
                , Just . pretty $ attemptedRewriteRule
                ]
            , "On configuration:"
            , Pretty.indent 2 . unparse $ configuration
            ]

showHashHex :: Int -> Text
showHashHex h = let w64 :: Word64 = fromIntegral h in Text.take 7 $ Text.pack $ showHex w64 ""

shortenRuleId :: Text -> Text
shortenRuleId msg = Text.take 8 msg

shortRuleIdTxt :: UniqueId -> Text
shortRuleIdTxt = shortenRuleId . fromMaybe "UNKNWON" . getUniqueId

instance Entry DebugAttemptedRewriteRules where
    entrySeverity _ = Debug
    helpDoc _ = "log attempted rewrite rules"

    oneLineContextDoc = \case
        (DebugAttemptedRewriteRules{configuration, ruleId, label}) ->
            [ Pretty.hsep ["term", Pretty.pretty . showHashHex $ hash configuration]
            , Pretty.hsep . map Pretty.pretty $
                ["rewrite", shortRuleIdTxt ruleId, fromMaybe "" label]
            ]

    oneLineDoc (DebugAttemptedRewriteRules{configuration, label, ruleId, attemptedRewriteRule}) =
        let x =
                map
                    (Pretty.brackets . Pretty.hsep)
                    [ ["detail"]
                    , ["term", Pretty.pretty . showHashHex $ hash configuration]
                    , ["rewrite", Pretty.pretty (shortRuleIdTxt ruleId), Pretty.pretty (fromMaybe "" label)]
                    ]
            y =
                ( Pretty.hsep . concat $
                    [ ["attempting to apply rewrite rule", Pretty.pretty (shortRuleIdTxt ruleId), Pretty.pretty label]
                    , ["at", Pretty.pretty attemptedRewriteRule]
                    , ["to term", Pretty.pretty . showHashHex $ hash configuration, Pretty.group $ unparse configuration]
                    ]
                )
         in mconcat x <> y

whileDebugAttemptRewriteRule ::
    MonadLog log =>
    Pattern RewritingVariableName ->
    UniqueId ->
    Maybe Text ->
    SourceLocation ->
    log a ->
    log a
whileDebugAttemptRewriteRule initial ruleId label attemptedRewriteRule =
    logWhile (DebugAttemptedRewriteRules{..})
  where
    configuration = mapConditionalVariables TermLike.mapVariables initial
    mapConditionalVariables mapTermVariables =
        Conditional.mapVariables mapTermVariables (pure toVariableName)

debugAttemptedRewriteRule ::
    MonadLog log =>
    Pattern RewritingVariableName ->
    UniqueId ->
    Maybe Text ->
    SourceLocation ->
    log ()
debugAttemptedRewriteRule initial ruleId label attemptedRewriteRule =
    logEntry DebugAttemptedRewriteRules{..}
  where
    configuration = mapConditionalVariables TermLike.mapVariables initial
    mapConditionalVariables mapTermVariables =
        Conditional.mapVariables mapTermVariables (pure toVariableName)
