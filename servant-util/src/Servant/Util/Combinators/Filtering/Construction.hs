{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE OverloadedLists  #-}
{-# LANGUAGE TypeInType       #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

-- | Helpers for defining filters manually.
module Servant.Util.Combinators.Filtering.Construction
    ( mkFilteringSpec
    , ($=)
    , ($~)
    ) where

import Universum hiding (filter)

import Data.Coerce (coerce)
import GHC.OverloadedLabels (IsLabel (..))
import GHC.TypeLits (ErrorMessage (..), KnownSymbol, TypeError)
import Servant (If)

import Servant.Util.Combinators.Filtering.Base
import Servant.Util.Combinators.Filtering.Filters
import Servant.Util.Combinators.Filtering.Support ()
import Servant.Util.Common

{- | Build a filtering specification.
Used along with "OverloadedLabels" extension and @($)@ / @($=)@ operators.

Example:

@
filteringSpec :: FilteringSpec ["id" ?: 'AutoFilter Int, "desc" ?: 'ManualFilter Text]
filteringSpec = mkFilteringSpec
    [ -- Constructing an auto filter
    , #id (FilterGT 0)

      -- The following three lines are equivalent
    , #id (FilterMatching 5)
    , #id $ FilterMatching 5
    , #id $= 5

      -- Constructing a manually implemented filter
    , #desc "You are my sunshine, my only sunshine"
    ]
@

You can freely use 'GHC.Exts.fromList' instead of this function.
-}
mkFilteringSpec :: [SomeFilter params] -> FilteringSpec params
mkFilteringSpec = FilteringSpec

type family IsSupportedFilter filter a :: Constraint where
    IsSupportedFilter filter a =
        If (Elem filter (SupportedFilters a))
          (() :: Constraint)
          (TypeError
              ( 'Text "Filter '" ':<>: 'ShowType filter ':<>:
                'Text "' is not supported for '" ':<>: 'ShowType a ':<>:
                'Text "' type"
              )
          )

-- | Safely construct 'TypeFilter'.
class MkTypeFilter filter fk a where
    mkTypeFilter :: filter -> TypeFilter fk a

instance ( filter ~ filterType a
         , IsAutoFilter filterType
         , IsSupportedFilter filterType a
         ) =>
         MkTypeFilter filter 'AutoFilter a where
    mkTypeFilter filter = TypeAutoFilter (SomeTypeAutoFilter filter)

instance (filter ~ a) => MkTypeFilter filter 'ManualFilter a where
    mkTypeFilter = TypeManualFilter

-- | Safely construct 'SomeFilter'.
class MkSomeFilter name filter (origParams :: [TyNamedFilter]) (params :: [TyNamedFilter]) where
    mkSomeFilter :: filter -> SomeFilter params

instance TypeError ('Text "Unknown filter " ':<>: 'ShowType name ':$$:
                    'Text "Allowed ones here: " ':<>: 'ShowType (TyNamedParamsNames origParams)) =>
         MkSomeFilter name filter origParams '[] where
    mkSomeFilter = error ":shrug:"

instance {-# OVERLAPPING #-}
         (MkTypeFilter filter fk a, KnownSymbol name, Typeable fk, Typeable a) =>
         MkSomeFilter name filter origParams ('TyNamedParam name (fk a) ': params) where
    mkSomeFilter filter =
        SomeFilter
        { sfName = symbolValT @name
        , sfFilter = mkTypeFilter @filter @fk @a filter
        }

instance MkSomeFilter name filter origParams params =>
         MkSomeFilter name filter origParams (param ': params) where
    mkSomeFilter filter = coerce $ mkSomeFilter @name @filter @origParams @params filter

-- | Filter can be raised to 'SomeFilter' which is part of 'FilteringSpec'.
instance MkSomeFilter name filter params params =>
         IsLabel name (filter -> SomeFilter params) where
    fromLabel = mkSomeFilter @name @_ @params

-- | Hint to provide a filter itself.
instance TypeError ('Text "Filter is missing") =>
         IsLabel name (SomeFilter params) where
    fromLabel = error "impossible"

-- | Construct a matching filter.
($=) :: (FilterMatching a -> SomeFilter params) -> a -> SomeFilter params
($=) f = f . FilterMatching
infixr 0 $=

-- | Construct a filter from a value with the same representation as expected one.
-- Helpful when newtypes are heavely used in API parameters.
($~) :: Coercible a b => (b -> SomeFilter params) -> a -> SomeFilter params
($~) f = f . coerce

_sample :: FilteringSpec ["id" ?: 'AutoFilter Int, "desc" ?: 'ManualFilter Text]
_sample =
    [ #id (FilterMatching 5)
    , #desc "Kek"
    , #id $ FilterGT 3
    ]