module EventSourcing.EventBus
  ( Handler
  , EventBus (..)
  , eventBus
  , registerHandler
  , registerProjection
  , publishEvent
  , storeAndPublishEvent
  ) where

import Control.Concurrent.Async
import Control.Concurrent.STM
import Control.Monad
import Control.Monad.IO.Class
import Data.Maybe (maybeToList)
import Pipes
import Pipes.Concurrent

import EventSourcing.ReadModel
import EventSourcing.Projection
import EventSourcing.Store

type Handler serialized m = StoredEvent serialized -> m ()

data EventBus event =
  EventBus
  { eventBusQueues :: TVar [Output (StoredEvent event)]
  }

eventBus :: IO (EventBus event)
eventBus = EventBus <$> atomically (newTVar [])

registerHandler
  :: (SequencedEventStore IO store serialized)
  => store -> EventBus serialized -> Handler serialized IO -> IO ()
registerHandler = registerHandlerStart 0

registerHandlerStart
  :: (SequencedEventStore IO store serialized)
  => SequenceNumber -> store -> EventBus serialized -> Handler serialized IO -> IO ()
registerHandlerStart seqNum store (EventBus queuesTVar) handler = do
  (output, input) <- spawn unbounded
  _ <- async $ do
    startPipe <- getSequencedEventsPipe store seqNum
    runEffect $ (startPipe >> fromInput input) >-> handlerConsumer handler
    performGC
  atomically $ modifyTVar' queuesTVar ((:) output)

registerProjection
  :: (ProjectionReadModel IO projstore proj, SequencedEventStore IO store serialized, Serializable (Event proj) serialized)
  => store -> EventBus serialized -> projstore -> IO ()
registerProjection eventStore bus projStore = do
  seqNum <- latestApplied projStore
  let handler event = applyEvents projStore (maybeToList $ deserializeEvent event)
  registerHandlerStart seqNum eventStore bus handler

handlerConsumer :: (Monad m) => Handler serialized m -> Consumer (StoredEvent serialized) m ()
handlerConsumer handler = forever $ await >>= lift . handler

publishEvent :: (MonadIO m) => EventBus serialized -> StoredEvent serialized -> m ()
publishEvent EventBus{..} event =
  liftIO $ void $ atomically $ do
    queues <- readTVar eventBusQueues
    mapM_ (`send` event) queues

storeAndPublishEvent
  :: (MonadIO m, EventStore m store proj, Serializable (Event proj) serialized)
  => store -> EventBus serialized -> AggregateId proj -> Event proj -> m ()
storeAndPublishEvent store bus uuid event = do
  storedEvents <- storeEvents store uuid [event]
  mapM_ (publishEvent bus) (serializeEvent <$> storedEvents)
