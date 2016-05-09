{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}
module JavaScript.WebSockets.Reflex.WebSocket 
  ( connect
  , Connection
  , Message(..)
  , receiveMessages
  , sendMessages
  , sendMessage
  , closed
  , counter, Counter, tick
  , blobs
  )
  where


import           Control.Concurrent          (MVar, newMVar, newEmptyMVar, putMVar, readMVar, modifyMVar)
import           Control.Monad               (when)
import           Control.Monad.IO.Class      (MonadIO, liftIO)
import           Data.JSString.Text          (textToJSString, textFromJSString)
import qualified Data.Map                 as Map
import           Data.Text                   (Text)
import           Data.Time.Clock             (getCurrentTime, utctDayTime)
import           JavaScript.Web.Blob         (Blob)
import           JavaScript.Web.CloseEvent   (CloseEvent)
import           JavaScript.Web.MessageEvent (MessageEvent, MessageEventData(..), getData)
import qualified JavaScript.Web.WebSocket as WS
import           Reflex
import           Reflex.Dom


data Message
  = TextMessage Text
  | BlobMessage Blob

instance Show Message where
  show (TextMessage t) = "text message:\n" ++ show t
  show (BlobMessage _) = "blob message"

data Connection t
  = Connection
    {
      socket   :: MVar WS.WebSocket
    , incoming :: Event t Message
    , closed   :: MVar CloseEvent
    , counter  :: Counter
    , blobs    :: MVar (Map.Map Text Blob)
    , debug    :: Bool
    }

newtype Counter
  = Counter (MVar Int)

newCounter :: IO Counter
newCounter = Counter <$> newMVar 0

tick :: Counter -> IO Int
tick (Counter m) = modifyMVar m (\ i -> return (succ i, i))

type Url
  = Text

connect :: forall (m :: * -> *) t.
  ( MonadWidget t m, MonadIO m
  ) => Bool -> Url -> m (Connection t)
connect debug_ u = do
  closed_ <- liftIO newEmptyMVar
  socket_ <- liftIO newEmptyMVar
  postBuild <- getPostBuild
  incoming_ <- performEventAsync . ffor postBuild . const $ \ trigger -> liftIO $ do
    connection <- WS.connect $ WS.WebSocketRequest
      { WS.url = textToJSString u
      , WS.protocols = []
      , WS.onMessage = Just $ if debug_
        then \ m -> do
          t <- utctDayTime <$> getCurrentTime
          putStrLn ("Incoming at " ++ show t ++ ": " ++ show (toMessage m))
          (trigger . toMessage) m
        else trigger . toMessage
      , WS.onClose = Just $ putMVar closed_
      }
    putMVar socket_ connection
  counter_ <- liftIO newCounter
  blobs_ <- liftIO $ newMVar Map.empty
  return $ Connection socket_ incoming_ closed_ counter_ blobs_ debug_

toMessage :: MessageEvent -> Message
toMessage = s . getData where
  s (StringData j)      = TextMessage $ textFromJSString j
  s (BlobData b)        = BlobMessage b
  s (ArrayBufferData _) = error "JavaScript.WebSockets.Reflex.WebSocket.toMessage: cannot handle ArrayBufferData"

-- |Receive messages on the given Connection as events.
receiveMessages :: forall t. Connection t -> Event t Message
receiveMessages = incoming

-- | Send messages to a connection.
-- | arguments are ordered this way so that one might use switchEvents e.g.
-- | switchEvents (sendMessage msg) :: Event Connection -> m (Event t ())  
-- | returns an Event for the success/failure of sending.
sendMessages :: (MonadWidget t m) => Event t Message -> Connection t -> m (Event t ())
sendMessages messages con = performEvent $ ffor messages
  $ \ m -> sendMessage m con

sendMessage :: (MonadIO m) => Message -> Connection t -> m ()
sendMessage m con = do
  t <- utctDayTime <$> liftIO getCurrentTime
  liftIO . putStrLn $ "Sending at " ++ show t ++ ": " ++ show m
  liftIO (readMVar $ socket con) >>= \ s -> case m of
    TextMessage t -> liftIO . flip WS.send s . textToJSString $ t
    BlobMessage b -> liftIO $ WS.sendBlob b s

-- |Disconnected event from message event.
-- disconnected :: Reflex t => Event t (Maybe SocketMsg) -> Event t ()
-- disconnected = unTag . ffilter isNothing

-- |Unwrap an event from message event, using the ghcjs_websockets WSReceivable
-- |Has instances for all Binary a and Text
-- |returns two events, successfully unwrapped messages and messages which could not be decoded
-- unwrapEvents :: (WSReceivable a, Reflex t) =>  Event t (Maybe SocketMsg) -> (Event t a, Event t SocketMsg)
-- unwrapEvents  = swap . splitEither . fmap WS.unwrapReceivable . catMaybesE


-- unwrapMaybe :: (SocketMsg -> Maybe a) -> SocketMsg -> Either SocketMsg a
-- unwrapMaybe f m = case f m of
--     Nothing   -> Left m
--     Just   a  -> Right a


-- unwrapWith :: Reflex t => (SocketMsg -> Maybe a) ->  Event t (Maybe SocketMsg) -> (Event t a, Event t SocketMsg)
-- unwrapWith f = swap . splitEither . fmap (unwrapMaybe f) . catMaybesE

    
-- |Decode a binary SocketMsg using the Binary class
-- |returns two events, successfully decoded messages and messages which could not be decoded  
-- decodeMessage :: (Binary a, Reflex t) => Event t (Maybe SocketMsg) -> (Event t a, Event t SocketMsg)  
-- decodeMessage = unwrapEvents


-- |Unwrap a text SocketMsg
-- |returns two events, messages which are Text, and messages are binary  
-- | e.g.  fst . textMessage <$> receiveMessages conn :: m (Event t Text) 
-- | 
-- textMessage :: (Reflex t) => Event t (Maybe SocketMsg) -> (Event t Text, Event t SocketMsg)  
-- textMessage = unwrapEvents


-- |Periodically check the latest connection is still open,
-- |the event is triggered when a connection is lost.
-- checkDisconnected :: MonadWidget t m => Int -> Connection -> m (Event t WS.ConnClosing)
-- checkDisconnected microSeconds conn = do 
--   poll <- tick microSeconds
--   e <- performEvent $ ffor poll (const $ liftIO $ WS.connectionCloseReason conn)
--   return (catMaybesE e)
  


-- | Send messages to a connection using WSSendable.
-- | instances for all Binary a and Text  
-- send :: (WSSendable a, MonadWidget t m) =>  Event t a -> Connection -> m (Event t Bool)
-- send a conn = performEvent $ ffor a $ liftIO . WS.send conn


 
