module EventSourcing.Store.Class
  ( EventStore (..)
  , ProjectionStore (..)
  ) where

import EventSourcing.Projection
import EventSourcing.UUID

-- Is the UUID part really necessary? Should that be handled in a StoredEvent
-- type?
class (Monad m) => EventStore store m event | store -> event where
  getUuids :: store -> m [UUID]
  getEvents :: store -> UUID -> m [event]
  storeEvents :: store -> UUID -> [event] -> m ()


-- data StoredEvent event
--   = StoredEvent
--   { storedEventEvent :: event
--   , storedEventSequenceNumber :: SequenceNumber
--   , storedEventTime :: UTCTime
--   }

-- newtype SequenceNumber = SequenceNumber { unSequenceNumber :: Int }
--   deriving (Show, Ord, Eq)


class (Projection proj, Monad m) => ProjectionStore store m proj | store -> proj where
  getProjection :: store -> UUID -> m proj
  applyEvents :: store -> UUID -> [Event proj] -> m ()

-- data StoredProjection proj
--   = StoredProjection
--   { storedProjectionProjection :: proj
--   , storedProjectionSequenceNumber :: SequenceNumber
--   } deriving (Show)
