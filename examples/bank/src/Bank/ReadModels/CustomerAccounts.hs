{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TupleSections #-}

module Bank.ReadModels.CustomerAccounts
  ( CustomerAccounts (..)
  , customerAccountsAccountsById
  , customerAccountsCustomerAccounts
  , customerAccountsCustomerIdsByName
  , getCustomerAccountsFromName
  , customerAccountsProjection
  ) where

import Control.Lens
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, mapMaybe)

import Eventful

import Bank.Aggregates.Account
import Bank.Events

-- | Groups account info by customer so it's easy to see all of a customer's
-- accounts
data CustomerAccounts
  = CustomerAccounts
  { _customerAccountsAccountsById :: Map UUID Account
  , _customerAccountsCustomerAccounts :: Map UUID [UUID]
  , _customerAccountsCustomerIdsByName :: Map String UUID
    -- NOTE: This assumes all customer names are unique. Obviously not true in
    -- the real world.
  } deriving (Show, Eq)

makeLenses ''CustomerAccounts

getCustomerAccountsFromName :: CustomerAccounts -> String -> [(UUID, Account)]
getCustomerAccountsFromName CustomerAccounts{..} name = fromMaybe [] $ do
  customerId <- Map.lookup name _customerAccountsCustomerIdsByName
  accountIds <- Map.lookup customerId _customerAccountsCustomerAccounts
  let lookupAccount uuid = (uuid,) <$> Map.lookup uuid _customerAccountsAccountsById
  return $ mapMaybe lookupAccount accountIds

handleCustomerAccountsEvent :: CustomerAccounts -> ProjectionEvent BankEvent -> CustomerAccounts
handleCustomerAccountsEvent accounts (ProjectionEvent uuid (CustomerCreatedEvent (CustomerCreated name))) =
  accounts
  & customerAccountsCustomerIdsByName %~ Map.insert name uuid
handleCustomerAccountsEvent accounts (ProjectionEvent uuid event@(AccountOpenedEvent (AccountOpened customerId _))) =
  accounts
  & customerAccountsAccountsById %~ Map.insert uuid account
  & customerAccountsCustomerAccounts %~ Map.insertWith (++) customerId [uuid]
  where
    account = projectionEventHandler accountProjection (projectionSeed accountProjection) event
-- Assume it's an account event. If it isn't it won't get handled, no biggy.
-- TODO: This feels nasty, we just blindly apply an event to an Account even if
-- it isn't an account event.
handleCustomerAccountsEvent accounts (ProjectionEvent uuid event) =
  accounts
  & customerAccountsAccountsById %~ Map.adjust modifyAccount uuid
  where
    modifyAccount account = projectionEventHandler accountProjection account event

customerAccountsProjection :: Projection CustomerAccounts (ProjectionEvent BankEvent)
customerAccountsProjection =
  Projection
  (CustomerAccounts Map.empty Map.empty Map.empty)
  handleCustomerAccountsEvent
