module Control.Concurrent.Pulse
    ( Pulse, newPulse, destroyPulse, withPulse, waitForPulse )
where

import Control.Concurrent
import Control.Concurrent.Async
import Control.Exception
import Control.Monad
import Data.IORef
import Data.Time.Clock
import qualified Data.Sequence as S

-- | A heartbeat
data Pulse
    = Pulse
    { p_worker :: !(Async ())
    , p_pending :: !(IORef (S.Seq (MVar ())))
    }

-- | Automatically calls 'newPulse' and 'destroyPulse' as needed
withPulse :: DiffTime -> (Pulse -> IO a) -> IO a
withPulse everySecs = bracket (newPulse everySecs) destroyPulse

-- | Create a new pulse that will send a heartbeat every 'DiffTime' seconds
newPulse :: DiffTime -> IO Pulse
newPulse everySecs =
    do pending <- newIORef S.empty
       worker <- async (pulseWorker everySecs pending)
       return (Pulse worker pending)

-- | Destroy the pulse. Note that all pending 'waitForPulse' will be left blocked
destroyPulse :: Pulse -> IO ()
destroyPulse p =
    do cancel (p_worker p)
       pure ()

pulseWorker :: DiffTime -> IORef (S.Seq (MVar ())) -> IO ()
pulseWorker everySecs pendingVar =
    forever $
    do threadDelay (round $ everySecs * 1000 * 1000)
       pending <- atomicModifyIORef' pendingVar (\p -> (S.empty, p))
       _ <- forConcurrently pending $ flip putMVar ()
       pure ()

-- | Block until the next heartbeat is triggered on the 'Pulse'
waitForPulse :: Pulse -> IO ()
waitForPulse p =
    do var <- newEmptyMVar
       _ <- atomicModifyIORef' (p_pending p) $ \x -> (x S.|> var, ())
       takeMVar var
{-# INLINE waitForPulse #-}
