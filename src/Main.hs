{-# LANGUAGE CPP #-}
module Main where
import Parse
import Eval
import LispVals
import Primitives
import LispEnvironment

import System.IO (hFlush, hPutStrLn, stderr, stdout)
import System.Environment (getArgs)
import Control.Monad (liftM, when)
import Control.Monad.Error (throwError)
#ifdef LIBEDITLINE
import System.Console.Editline.Readline (readline, addHistory, setInhibitCompletion)
#else
import System.Console.Readline (readline, addHistory, setInhibitCompletion)
#endif
import Data.Char (isSpace)

main :: IO ()
main = do args <- getArgs
          if null args then runRepl else runOne $ args

evalString :: Env -> String -> IO (String, Env)
evalString env expr = runIOThrows (liftM show ((liftThrows $ readExpr expr) >>= eval)) env

evalAndPrint :: Env -> String -> IO Env
evalAndPrint env expr = do
    (out, newEnv) <- evalString env expr
    putStrLn out
    return newEnv

runOne :: [String] -> IO ()
runOne args = do
    (out, _) <- runIOThrows (liftM show
            (bindVars [("args", List $ map String $ drop 1 args)] >> eval (List [Atom "load", String (args !! 0)])))
        primitiveBindings
    hPutStrLn stderr out

runRepl :: IO ()
runRepl = do
    setInhibitCompletion True
    replLoop primitiveBindings

doQuit :: IO Bool
doQuit = putStrLn "Leaving tlisp" >> return False

doHelp :: IO ()
doHelp = putStrLn "Welcome to tlisp!\n\t:quit\t\tExits the repl\n\t:help\t\tThis message"

showBinding :: (String, LispVal) -> String
showBinding (s,l) = s ++ " -> " ++ show l

doEnv :: Env -> IO ()
doEnv e = putStrLn $ unlines $ map (showBinding) $ envToList e

handleCommand :: Env -> String -> IO Bool
handleCommand e s = case s of
    "quit" -> doQuit
    "q" -> doQuit
    "help" -> doHelp >> return True
    "h" -> doHelp >> return True
    "env" -> doEnv e >> return True
    "e" -> doEnv e >> return True
    _ -> putStrLn ("Unknown command :" ++ s) >> return True

replLoop :: Env -> IO ()
replLoop env = do
    maybeLine <- readline "tlisp>>> "
    case maybeLine of
        Nothing -> return ()
        Just line -> do
            let trimmedLine = dropWhile (isSpace) line
            if (not $ null trimmedLine)
            then do
                addHistory trimmedLine
                case trimmedLine of
                    (':':command) -> do
                        continue <- handleCommand env command
                        if continue then
                            replLoop env
                        else
                            return ()
                    _ -> evalAndPrint env trimmedLine >>= replLoop
            else
                replLoop env

primitiveBindings :: Env
primitiveBindings = envFromList (map (makeFunc IOFunc) ioPrimitives ++ (map (makeFunc PrimitiveFunc) primitives))
    where makeFunc constructor (var, func) = (var, constructor func)
