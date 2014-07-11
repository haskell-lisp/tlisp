{-# LANGUAGE FlexibleContexts #-}
module LispEnvironment where
import LispVals

import Control.Monad (liftM, mapM)
import Control.Monad.State (get, put, runStateT)
import Control.Monad.State.Class (MonadState)
import Control.Monad.Error (ErrorT, runErrorT, throwError, MonadError, catchError)
import Control.Monad.Error.Class (MonadError)
import Control.Monad.IO.Class (liftIO)
import qualified Data.Map as M (empty, lookup, insert, fromList, union, toList)

envFromList :: [(String, LispVal)] -> Env
envFromList = M.fromList

envToList :: Env -> [(String, LispVal)]
envToList = M.toList

liftThrows :: ThrowsError a -> IOThrowsError a
liftThrows (Left err) = throwError err
liftThrows (Right val) = return val

runIOThrows :: IOThrowsError String -> Env -> IO (String, Env)
runIOThrows action env = do
        (a, s) <- runStateT (runErrorT (trapError action)) env
        return $ (extractValue a, s)
    where trapError action = catchError action (return . show)

extractValue :: ThrowsError a -> a
extractValue (Right val) = val

getEnv :: MonadState Env m => m Env
getEnv = get

putEnv :: MonadState Env m => Env -> m ()
putEnv = put

getVar :: (MonadState Env m, MonadError LispError m) => String -> m LispVal
getVar var = get >>= maybe (throwError $ UnboundVar "Getting an unbound variable" var) (return) . M.lookup var

setVar :: (MonadState Env m, MonadError LispError m) => String -> LispVal -> m LispVal
setVar var value = get >>= \e -> maybe
            (throwError $ UnboundVar "Setting an unbound variable" var)
            (const $ put $ M.insert var value e) (M.lookup var e)
        >> return value

defineVar :: (MonadState Env m) => String -> LispVal -> m LispVal
defineVar var value = get >>= put . (M.insert var value) >> return value

bindVars :: (MonadState Env m) => [(String, LispVal)] -> m ()
bindVars bindings = get >>= extendEnv bindings >>= put
    where extendEnv bindings env = return (M.union (envFromList bindings) env)

