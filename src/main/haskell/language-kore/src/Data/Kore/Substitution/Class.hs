{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
module Data.Kore.Substitution.Class ( SubstitutionClass (..)
                                    , PatternSubstitutionClass (..)
                                    ) where

import           Control.Monad.Reader            (ReaderT, ask, runReaderT,
                                                  withReaderT)
import           Data.Maybe                      (isJust)
import qualified Data.Set                        as Set
import           Prelude                         hiding (lookup)

import           Data.Kore.AST
import           Data.Kore.ASTTraversals         (topDownVisitorM)
import           Data.Kore.Substitution.MapClass
import           Data.Kore.Variables.Free
import           Data.Kore.Variables.Fresh.Class

{-|'SubstitutionClass' represents a substitution type @s@ mapping variables
of type @v@ to terms of type @t@.
-}
class MapClass s v t => SubstitutionClass s v t where
    getFreeVars :: s -> Set.Set v
    addBinding :: v -> t -> s -> s
    removeBinding :: v -> s -> s

{-'SubstitutionWithFreeVars' is a substitution which can hold more free
variables than its terms can.  'freeVars' is used to track the free variables
in a substitution context.
-}
data SubstitutionWithFreeVars s var = SubstitutionWithFreeVars
    { substitution :: s
    , freeVars     :: Set.Set (UnifiedVariable var)
    }

addFreeVariable
    :: Ord (UnifiedVariable var)
    => UnifiedVariable var
    -> SubstitutionWithFreeVars s var
    -> SubstitutionWithFreeVars s var
addFreeVariable v s = s { freeVars = v `Set.insert` freeVars s }

instance ( SubstitutionClass s (UnifiedVariable var) (FixedPattern var))
    => MapClass (SubstitutionWithFreeVars s var)
        (UnifiedVariable var) (FixedPattern var)
  where
    isEmpty = isEmpty . substitution
    lookup v = lookup v . substitution
    toList = toList . substitution
    fromList l = let s = fromList l in SubstitutionWithFreeVars
        { substitution = s
        , freeVars = getFreeVars s
        }

instance ( VariableClass var
         , SubstitutionClass s (UnifiedVariable var) (FixedPattern var)
         ) => SubstitutionClass (SubstitutionWithFreeVars s var)
            (UnifiedVariable var) (FixedPattern var)
  where
    removeBinding v s = s { substitution = removeBinding v (substitution s) }
    addBinding v t s =
        s { substitution = addBinding v t (substitution s)
          , freeVars = freeVars s `Set.union` freeVariables t
          }
    getFreeVars = freeVars

{-|'PatternSubstitutionClass' defines a generic 'substitute' function
which given a 'FixedPattern' @p@ and an @s@ of class 'SubstitutionClass',
applies @s@ on @p@ in a monadic state used for generating fresh variables.
-}
class ( SubstitutionClass s (UnifiedVariable var) (FixedPattern var)
      , FreshVariablesClass m var
      ) => PatternSubstitutionClass var s m
  where
    substitute
        :: FixedPattern var
        -> s
        -> m (FixedPattern var)
    substitute p s = runReaderT (substituteM p) SubstitutionWithFreeVars
        { substitution = s
        , freeVars = freeVariables p `Set.union` getFreeVars s
        }

substituteM
    :: PatternSubstitutionClass var s m
    => FixedPattern var
    -> ReaderT (SubstitutionWithFreeVars s var) m (FixedPattern var)
substituteM = topDownVisitorM substitutePreprocess substituteVariable

substituteVariable
    :: (IsMeta a, PatternSubstitutionClass var s m)
    => Pattern a var (FixedPattern var)
    -> ReaderT (SubstitutionWithFreeVars s var) m (FixedPattern var)
substituteVariable (VariablePattern v) = do
    subst <- substitution <$> ask
    case lookup (asUnifiedVariable v) subst of
        Just up -> return up
        Nothing -> return $ asUnifiedPattern (VariablePattern v)
substituteVariable p = return $ asUnifiedPattern p

{-
* if the substitution is empty, return the pattern unchanged;
* if the pattern is a binder, handle using 'binderPatternSubstitutePreprocess'
* if the pattern is not a binder recurse.
-}
substitutePreprocess
    :: (IsMeta a, PatternSubstitutionClass var s m)
    => Pattern a var (FixedPattern var)
    -> ReaderT (SubstitutionWithFreeVars s var)
        m (Either (FixedPattern var) (Pattern a var (FixedPattern var)))
substitutePreprocess p
  = do
    s <- ask
    if isEmpty s then return $ Left (asUnifiedPattern p)
    else case p of
        ExistsPattern e -> binderPatternSubstitutePreprocess s e
        ForallPattern f -> binderPatternSubstitutePreprocess s f
        _               -> return $ Right p

{-
* if the quantified variable is among the encountered free variables
  in this contex, add an alpha-renaming binding to the substitution
* if the quantified variable is replaced by this substitution,
  susbtitute the body using the substitution without this variable
* otherwise, do a full substitution of the body (remembering that, in this
  context, the quantified variable is free).
-}
binderPatternSubstitutePreprocess
    :: (MLBinderPatternClass q, PatternSubstitutionClass var s m, IsMeta a)
    => SubstitutionWithFreeVars s var
    -> q a var (FixedPattern var)
    -> ReaderT (SubstitutionWithFreeVars s var)
        m (Either (FixedPattern var) (Pattern a var (FixedPattern var)))
binderPatternSubstitutePreprocess s q
    | var `Set.member` vars
      = do
        var' <- freshVariableSuchThat var (not . (`Set.member` vars))
        substituteBinderBodyWith var'
            (addBinding var (unifiedVariableToPattern var'))
    | isJust (lookup var s) = substituteFreeBinderBodyWith (removeBinding var)
    | otherwise = substituteFreeBinderBodyWith id
  where
    sort = getBinderPatternSort q
    var = getBinderPatternVariable q
    pat = getBinderPatternPattern q
    vars = getFreeVars s
    substituteBinderBodyWith newVar fs =
        (Left . asUnifiedPattern . binderPatternConstructor q sort newVar) <$>
            withReaderT fs (substituteM pat)
    substituteFreeBinderBodyWith fs =
        substituteBinderBodyWith var (addFreeVariable var . fs)
