{- |
Copyright   : (c) Runtime Verification, 2022
License     : BSD-3-Clause
-}
module Kore.Syntax.ParsedKore (
    -- * Parsing
    parseKoreDefinition,
    parseKorePattern,
    decodeJsonKoreDefinition,
    encodeJsonKoreDefinition,

    -- * Validating and converting
    internalise,
) where

import Control.Monad.Trans.Except (runExcept)
import Data.Aeson qualified as Json
import Data.Aeson.Encode.Pretty qualified as Json
import Data.ByteString.Lazy (ByteString)
import Data.Text (Text)

import Kore.Definition.Base
import Kore.Syntax.Json qualified as KoreJson
import Kore.Syntax.ParsedKore.Base
import Kore.Syntax.ParsedKore.Internalise as Internalise
import Kore.Syntax.ParsedKore.Parser qualified as Parser

-- Parsing text

{- | Parse a string representing a Kore definition.

@parseKoreDefinition@ returns a 'KoreDefinition' upon success, or a parse error
message otherwise. The input must contain a valid Kore definition and nothing
else.
-}
parseKoreDefinition ::
    -- | Filename used for error messages
    FilePath ->
    -- | The concrete syntax of a valid Kore definition
    Text ->
    Either String ParsedDefinition
parseKoreDefinition = Parser.parseDefinition

{- | Parse a string representing a Kore pattern.

@parseKorePattern@ returns a 'ParsedPattern' upon success, or a parse error
message otherwise. The input must contain a valid Kore pattern and nothing else.
-}
parseKorePattern ::
    -- | Filename used for error messages
    FilePath ->
    -- | The concrete syntax of a valid Kore pattern
    Text ->
    Either String KoreJson.KorePattern
parseKorePattern = Parser.parsePattern

-- Parsing and encoding Json

{- | Read a Kore definition from Json.

Reads a Kore definition, returning a @ParsedDefinition@ or an error message.
To read a single @KorePattern@, use @Kore.Syntax.Json.decodePattern@.
-}
decodeJsonKoreDefinition :: ByteString -> Either String ParsedDefinition
decodeJsonKoreDefinition = Json.eitherDecode'

{- | Encode a @ParsedDefinition@ as Json

Uses the aeson-pretty encoding for KorePatterns, but no additions for
the additional types.
-}
encodeJsonKoreDefinition :: ParsedDefinition -> ByteString
encodeJsonKoreDefinition = Json.encodePretty' KoreJson.prettyJsonOpts

-- internalising parsed data
internalise :: ParsedDefinition -> Either DefinitionError KoreDefinition
internalise = runExcept . Internalise.buildDefinition
